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
            local test_util = require("test_util")

            local datas = {"ab", "cd", "e"}

            local data, err_code, err_msg = test_util.test_writer(datas)
            if err_code ~= nil then
                ngx.log(ngx.ERR, err_code, ":", err_msg)
                return
            end

            ngx.say(data)
        ';
    }
--- request
GET /t
--- response_body_like
2;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
ab\r
2;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
cd\r
1;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
e\r
0;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
\r

--- no_error_log
[error]

=== TEST 2: test chunk headers
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local aws_chunk_writer = require("resty.aws_chunk.writer")

            local cases = {
                {1, 1, {["Content-Length"]=173, ["x-amz-decoded-content-length"]=1}},
                {2, 2, {["Content-Length"]=174, ["x-amz-decoded-content-length"]=2}},
                {2, 1, {["Content-Length"]=260, ["x-amz-decoded-content-length"]=2}},
                {10, 3, {["Content-Length"]=440, ["x-amz-decoded-content-length"]=10}},
                }

            for _, case in ipairs(cases) do
                local data_size, chunk_size, exp_headers = unpack(case)

                local headers = aws_chunk_writer.make_chunk_headers(data_size, chunk_size)
                if headers["x-amz-decoded-content-length"] ~= exp_headers["x-amz-decoded-content-length"]
                    or headers["Content-Length"] ~= exp_headers["Content-Length"] then

                    ngx.log(ngx.ERR, "test failed", data_size, ",", chunk_size, ",", headers["Content-Length"])
                    return
                end

                ngx.say("ok")
            end
        ';
    }
--- request
GET /t
--- response_body_like
ok

--- no_error_log
[error]
