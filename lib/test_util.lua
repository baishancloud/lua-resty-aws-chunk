local aws_chunk_reader = require("resty.aws_chunk.reader")
local aws_chunk_writer = require("resty.aws_chunk.writer")

local _M = {}

function _M.test_reader(pread_size, read_size, opts)
    local chunk_reader, err_code, err_msg = aws_chunk_reader:new(opts)
    if err_code ~= nil then
        return nil, err_code, err_msg
    end

    if pread_size ~= nil then
        local buf, err_code, err_msg = chunk_reader:pread(pread_size)
        if err_code ~= nil then
            return nil, err_code, err_msg
        end
    end

    local bufs = {}
    while true do
        local buf, err_code, err_msg = chunk_reader:read(read_size)
        if err_code ~= nil then
            return nil, err_code, err_msg
        end

        if buf == "" then
            break
        end

        table.insert(bufs, buf)
    end

    return table.concat(bufs)
end

function _M.test_writer(datas, v4signer, v4signer_ctx)
    local chunk_writer = aws_chunk_writer:new(v4signer, v4signer_ctx)

    local chunk_data = {}
    for _, d in ipairs(datas) do
        table.insert(chunk_data, chunk_writer:make_chunk(d))
    end

    -- last chunk
    table.insert(chunk_data, chunk_writer:make_chunk(""))

    return table.concat(chunk_data)
end
return _M
