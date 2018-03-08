# vim:set ft=lua ts=4 sw=4 et:

use Test::Nginx::Socket 'no_plan';

use Cwd qw(cwd);
my $pwd = cwd();

no_long_string();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    lua_package_cpath "$pwd/lib/?.so;;";
};

run_tests();

__DATA__

=== TEST 1: basic
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local aws_chunk_reader = require("resty.aws_chunk.reader")

            local chunk_reader, err_code, err_msg = aws_chunk_reader:new({
                timeout = 60 * 1000,
                block_size = 1024,
            })

            if err_code ~= nil then
                ngx.log(ngx.ERR, err_code, ":", err_msg)
                return
            end

            local buf, err_code, err_msg = chunk_reader:pread(2)
            if err_code ~= nil then
                ngx.log(ngx.ERR, err_code, ":", err_msg)
                return
            end

            local bufs = {}
            while true do
                local buf, err_code, err_msg = chunk_reader:read(1)
                if err_code ~= nil then
                    ngx.log(ngx.ERR, err_code, ":", err_msg)
                    --ngx.exit(500)
                    return
                end

                if buf == "" then
                    break
                end

                table.insert(bufs, buf)
            end

            ngx.say(table.concat(bufs))

        ';
    }
--- more_headers
x-amz-content-sha256: STREAMING-AWS4-HMAC-SHA256-PAYLOAD
x-amz-decoded-content-length: 4

--- request eval
"PUT /t HTTP/1.1
2;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
aa\r
2;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
bb\r
0;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
\re
"

--- response_body_like
aabb
--- no_error_log
[error]
