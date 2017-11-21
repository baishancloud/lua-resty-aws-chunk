local resty_sha256 = require('resty.sha256')
local resty_string = require('resty.string')
local err_socket = require( "acid.err_socket" )
local rpc_logging = require('acid.rpc_logging')
local constants = require('resty.aws_chunk.constants')
local aws_authenticator = require('resty.awsauth.aws_authenticator')

local _M = {}
local mt = { __index = _M }

local has_logging = true
local CRLF = '\r\n'

local function discard_read( self, size )
    local buf, errmes = self.sock:receive( size )
    if errmes ~= nil then
        return nil, err_socket.to_code(errmes),
            'read data error. ' .. tostring(errmes)
    end
end

local function read_body( self, size )
    if size <= 0 then
        return ''
    end

    rpc_logging.reset_start(self.log)
    local buf, errmes = self.sock:receive( size )
    rpc_logging.incr_stat(self.log, 'downstream', 'recvbody', #(buf or ''))

    if errmes ~= nil then
        local err = err_socket.to_code(errmes)
        rpc_logging.set_err(self.log, err)

        return nil, err, 'read data error. ' .. tostring(errmes)
    end

    return buf
end

local function read_chunk_meta( self )
    local meta_line, errmes = self.sock:receiveuntil(CRLF)()
    if errmes ~= nil then
        return nil, err_socket.to_code(errmes),
            'read chunk metadata error. ' .. tostring(errmes)
    end

    local size, sign = string.match(meta_line, constants.ptn_chunk_meta)
    if size == nil or tonumber(size, 16) == nil or sign == nil then
        ngx.log(ngx.INFO, 'invalid chunk metadata:'.. tostring(meta_line))
        return nil, 'InvalidRequest', 'Invalid chunk metadata'
    end

    return {size = tonumber(size, 16), sign = sign}
end

local function start_chunk( self )
    local meta, err, errmes = read_chunk_meta( self )
    if err ~= nil then
        return nil, err, errmes
    end

    local chunk = {
        size = meta.size,
        sign = meta.sign,
        pos  = 0,
    }

    if self.authenticator ~= nil then
        chunk.sha256 = resty_sha256:new()
    end

    return chunk
end

local function read_chunk_data( self, chunk, size )
    size = math.min(size, chunk.size - chunk.pos)

    local buf, err, errmes = read_body(self, size)
    if err ~= nil then
        return nil, err, errmes
    end

    if chunk.sha256 ~= nil then
        chunk.sha256:update(buf)
    end

    chunk.pos = chunk.pos + #buf

    return buf
end

local function end_chunk(self, chunk)
    -- chunk end, ignore '\r\n'
    local _, err, errmes = discard_read(self, #CRLF)
    if err ~= nil then
        return nil, err, errmes
    end

    if chunk.sha256 ~= nil and chunk.sign ~= constants.fake_signature then
        local bin_sha256 = chunk.sha256:final()
        local hex_sha256 = resty_string.to_hex(bin_sha256)

        local _, err, errmes = self.authenticator:check_chunk_signature(
                                    self.sign_ctx, hex_sha256, chunk.sign)
        if err ~= nil then
            return nil, 'InvalidRequest', tostring(err) .. ':' .. tostring(errmes)
        end
    end

    return nil, nil, nil
end

local function read_from_predata(self, size)
    local psize = #self.pread_data
    local data = ''

    if psize == 0 then
        return data
    elseif psize <= size then
        data = self.pread_data
        self.pread_data = ''
    else
        data = string.sub(self.pread_data, 1, size)
        self.pread_data = string.sub(self.pread_data, size + 1)
    end

    return data
end

local function read_chunk(self, bufs, size)
    while size > 0 do

        if self.chunk == nil then
            local chunk, err, errmes = start_chunk(self)
            if err ~= nil then
                return nil, err, errmes
            end
            self.chunk = chunk
        end

        local chunk = self.chunk

        local read_size = math.min(size, self.block_size)
        local buf, err, errmes = read_chunk_data(self, chunk, read_size)
        if err ~= nil then
            return nil, err, errmes
        end

        table.insert( bufs, buf )

        local buf_size = #buf
        size = size - buf_size
        self.read_size = self.read_size + buf_size

        if chunk.pos == chunk.size then
            local _, err, errmes = end_chunk(self, chunk)
            if err ~= nil then
                return nil, err, errmes
            end
            self.chunk = nil
        end

        if chunk.size == 0 then
            self.read_eof = true
            break
        end
    end

    return bufs
end

local function get_chunk_headers(headers)
    local hdrs = {
        ['x-amz-content-sha256'] = headers['x-amz-content-sha256'],
        ['x-amz-decoded-content-length'] =
            tonumber(headers['x-amz-decoded-content-length']),
    }

    if hdrs['x-amz-content-sha256'] ~= 'STREAMING-AWS4-HMAC-SHA256-PAYLOAD' then
        return
    end

    if hdrs['x-amz-decoded-content-length'] == nil then
        return nil, 'InvalidRequest', 'Invalid x-amz-decoded-content-length'
    end

    return hdrs
end

local function init_chunk_sign(self, sk, bucket, signing_key)
    if type(sk) ~= 'function'
        or type(bucket) ~= 'function'
        or type(signing_key) == nil then

        return nil, 'InvalidArgument', 'Lack chunk signature argument'
    end

    local auth = aws_authenticator.new(sk , bucket, signing_key)

    local ctx, err, errmes = auth:init_seed_signature()
    if err ~= nil then
        if err == 'InvalidSignature' then
            ngx.log(ngx.WARN, 'aws chunk upload ssing non-v4 signatures')
            return
        end
        return nil, err, errmes
    end

    self.sign_ctx = ctx
    self.authenticator = auth
end

function _M.new(_, opts)
    local opts = opts or {}
    local headers = ngx.req.get_headers(0)
    local method = ngx.var.request_method

    local body_size, err, errmes = _M.get_body_size(headers)
    if err ~= nil then
        return nil, err, errmes
    end

    local sock, err
    if body_size > 0 then
        sock, err = ngx.req.socket()
        if not sock then
            return nil, 'InvalidRequest', err
        end
        sock:settimeout(opts.timeout or 60000)
    end

    local obj = {
        sock = sock,

        block_size = opts.block_size or 1024 * 1024,

        read_size = 0,
        body_size = body_size,

        pread_data = ''
    }
    obj.read_eof = obj.body_size == obj.read_size

    if has_logging then
        obj.log = rpc_logging.new_entry(opts.service_key or 'put_client')
        rpc_logging.add_log(obj.log)
    end

    local is_aws_chunk, err, errmes = _M.is_aws_chunk(method, headers)
    if err ~= nil then
        return nil, err, errmes
    end

    if is_aws_chunk then
        obj.chunk = nil
        obj.aws_chunk = true

        if opts.check_signature == true then

            local rst, err, errmes = init_chunk_sign(obj, opts.get_secret_key,
                         opts.get_bucket_or_host, opts.shared_signing_key)
            if err ~= nil then
                return nil, err, errmes
            end
        end
    end

    return setmetatable( obj, mt )
end

local function read_normal(self, bufs, size)
    while size > 0 do

        local read_size = math.min(size,
             self.block_size, self.body_size - self.read_size)

        local buf, err, errmes = read_body(self, read_size)
        if err ~= nil then
            return nil, err, errmes
        end

        table.insert( bufs, buf )

        local buf_size = #buf
        self.read_size = self.read_size + buf_size
        size = size - buf_size

        if self.read_size == self.body_size then
            self.read_eof = true
            break
        end
    end

    return bufs
end

function _M.read(self, size)
    local bufs = {}

    local pread_data = read_from_predata(self, size)
    if pread_data ~= '' then
        table.insert(bufs, pread_data)
        size = size - #pread_data
    end

    if self.read_eof then
        return table.concat(bufs)
    end

    local _, err_code, err_msg
    if self.aws_chunk then
        _, err_code, err_msg = read_chunk(self, bufs, size)
    else
        _, err_code, err_msg = read_normal(self, bufs, size)
    end

    if err_code ~= nil then
        return nil, err_code, err_msg
    end

    return table.concat(bufs)
end

function _M.pread(self, size)
    local data, err_code, err_msg = _M.read(self, size)
    if err_code ~= nil then
        return nil, err_code, err_msg
    end

    if data == '' then
        return data
    end

    self.pread_data = data .. self.pread_data
    return data
end

function _M.get_body_size(headers)
    local content_length = tonumber(headers['content-length'])

    if content_length == nil then
        return nil, 'InvalidRequest', 'Content-Length is nil'
    end

    local hdrs, err, errmes = get_chunk_headers(headers)
    if err ~= nil then
        return nil, err, errmes
    end

    if hdrs ~= nil then
        content_length = hdrs['x-amz-decoded-content-length']
    end

    return content_length
end

function _M.is_aws_chunk(method, headers)
    if string.upper(method) ~= 'PUT' then
        return false
    end

    local hdrs, err, errmes = get_chunk_headers(headers)

    return hdrs ~= nil, err, errmes
end

function _M.is_eof(self)
    return self.read_eof == true and self.pread_data == ''
end

return _M
