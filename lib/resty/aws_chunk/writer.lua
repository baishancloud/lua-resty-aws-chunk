local resty_sha256 = require('resty.sha256')
local resty_string = require('resty.string')
local constants = require('resty.aws_chunk.constants')

local _M = {}
local mt = { __index = _M }

local CRLF = '\r\n'

local function concat_chunk_meta(size, sign)
    return string.format(constants.fmt_chunk_meta, size, sign)
end

local function end_chunk()
    return CRLF
end

local function make_content_length(data_size, max_chunk_body_size)
    local body_size = 0

    while true do
        local chunk_body_size = math.min(data_size, max_chunk_body_size)

        local chunk_meta = concat_chunk_meta(
            chunk_body_size, constants.fake_signature)

        local chunk_size = #chunk_meta + chunk_body_size + #end_chunk()

        body_size = body_size + chunk_size
        data_size = data_size - chunk_body_size

        if chunk_body_size == 0 then
            break
        end
    end

    return body_size
end

function _M.new(_, v4signer, v4signer_ctx)
    local obj = {
        v4signer = v4signer,
        v4signer_ctx = v4signer_ctx,
    }

    if v4signer ~= nil then
        v4signer:init_seed_signature(v4signer_ctx)
    end

    return setmetatable(obj, mt)
end

function _M.fake_chunk_sign(self)
    return constants.fake_signature
end

function _M.make_chunk_sign(self, data)
    local alg_sha256 = resty_sha256:new()
    alg_sha256:update(data)
    local hex_sha256 = resty_string.to_hex(alg_sha256:final())

    return self.v4signer:get_chunk_signature(self.v4signer_ctx, hex_sha256)
end

function _M.make_chunk_meta(self, data)
    local sign = _M.make_chunk_sign(self, data)
    return concat_chunk_meta(#data, sign)
end

function _M.fake_chunk_meta(self, data)
    local sign = _M.fake_chunk_sign(self)
    return concat_chunk_meta(#data, sign)
end

function _M.end_chunk(self)
    return end_chunk()
end

function _M.make_chunk(self, chunk_data)
    local chunk_meta

    if self.v4signer == nil then
        chunk_meta = _M.fake_chunk_meta(self, chunk_data)
    else
        chunk_meta = _M.make_chunk_meta(self, chunk_data)
    end

    return table.concat({chunk_meta, chunk_data, _M.end_chunk(self)})
end

function _M.chunk_headers(data_size, content_length)
    return {
        ['Content-Length'] = content_length,
        ['Content-Encoding'] = 'aws-chunked',
        ['x-amz-content-sha256'] = 'STREAMING-AWS4-HMAC-SHA256-PAYLOAD',
        ['x-amz-decoded-content-length'] = data_size,
    }
end

function _M.make_chunk_headers(data_size, chunk_size)
    local cl = make_content_length(data_size, chunk_size)
    return _M.chunk_headers(data_size, cl)
end

return _M
