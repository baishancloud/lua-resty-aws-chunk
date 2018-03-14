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
            local data, err_code, err_msg = test_util.test_reader(1, 2)
            if err_code ~= nil then
                ngx.log(ngx.ERR, err_code, ":", err_msg)
                return
            end

            ngx.say(data)
        ';
    }
--- more_headers
x-amz-content-sha256: STREAMING-AWS4-HMAC-SHA256-PAYLOAD
x-amz-decoded-content-length: 22

--- request eval
"PUT /t HTTP/1.1
a;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
abcdefjikl\r
c;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
123456789012\r
0;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
\r\ne
"
--- response_body_like
abcdefjikl123456789012
--- no_error_log
[error]


=== TEST 2: test small Content-Length
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local test_util = require("test_util")
            local data, err_code, err_msg = test_util.test_reader(1, 2)
            if err_code ~= nil then
                ngx.log(ngx.ERR, err_code, ":", err_msg)
                return
            end

            ngx.say(data)
        ';
    }
--- more_headers
x-amz-content-sha256: STREAMING-AWS4-HMAC-SHA256-PAYLOAD
x-amz-decoded-content-length: 22
Content-Length:10

--- request eval
"PUT /t HTTP/1.1
a;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
abcdefjikl\r
c;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
123456789012\r
0;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
\re
"

--- error_log
InvalidRequest:read body error


=== TEST 3: test large Content-Length
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local test_util = require("test_util")
            local data, err_code, err_msg = test_util.test_reader(1, 2)
            if err_code ~= nil then
                ngx.log(ngx.ERR, err_code, ":", err_msg)
                return
            end

            ngx.say(data)
        ';
    }
--- more_headers
x-amz-content-sha256: STREAMING-AWS4-HMAC-SHA256-PAYLOAD
x-amz-decoded-content-length: 22
Content-Length:10240000

--- request eval
"PUT /t HTTP/1.1
a;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
abcdefjikl\r
c;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
123456789012\r
0;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
\r\ne
"
--- response_body_like
abcdefjikl123456789012
--- no_error_log
[error]

=== TEST 4: test Invalid x-amz-decoded-content-length
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local test_util = require("test_util")
            local data, err_code, err_msg = test_util.test_reader(1, 2)
            if err_code ~= nil then
                ngx.log(ngx.ERR, err_code, ":", err_msg)
                return
            end

            ngx.say(data)
        ';
    }
--- more_headers
x-amz-content-sha256: STREAMING-AWS4-HMAC-SHA256-PAYLOAD
x-amz-decoded-content-length: 1
Content-Length:10240000

--- request eval
"PUT /t HTTP/1.1
a;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
abcdefjikl\r
c;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
123456789012\r
0;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
\r\ne
"
--- response_body_like
abcdefjikl123456789012
--- no_error_log
[error]


=== TEST 5: test nil x-amz-decoded-content-length
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local test_util = require("test_util")
            local data, err_code, err_msg = test_util.test_reader(1, 2)
            if err_code ~= nil then
                ngx.log(ngx.ERR, err_code, ":", err_msg)
                return
            end

            ngx.say(data)
        ';
    }
--- more_headers
x-amz-content-sha256: STREAMING-AWS4-HMAC-SHA256-PAYLOAD

--- request eval
"PUT /t HTTP/1.1
a;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
abcdefjikl\r
c;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
123456789012\r
0;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
\r\ne
"
--- error_log
InvalidRequest:Invalid x-amz-decoded-content-length


=== TEST 6: test Invalid aws chunk the size of metaline
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local test_util = require("test_util")
            local data, err_code, err_msg = test_util.test_reader(1, 2)
            if err_code ~= nil then
                ngx.log(ngx.ERR, err_code, ":", err_msg)
                return
            end

            ngx.say(data)
        ';
    }
--- more_headers
x-amz-content-sha256: STREAMING-AWS4-HMAC-SHA256-PAYLOAD
x-amz-decoded-content-length: 22

--- request eval
"PUT /t HTTP/1.1
5;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
abcdefjikl\r
c;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
123456789012\r
0;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
\r\ne
"
--- error_log
InvalidRequest:Invalid chunk end


=== TEST 7: test Invalid aws chunk metaline format
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local test_util = require("test_util")
            local data, err_code, err_msg = test_util.test_reader(1, 2)
            if err_code ~= nil then
                ngx.log(ngx.ERR, err_code, ":", err_msg)
                return
            end

            ngx.say(data)
        ';
    }
--- more_headers
x-amz-content-sha256: STREAMING-AWS4-HMAC-SHA256-PAYLOAD
x-amz-decoded-content-length: 22

--- request eval
"PUT /t HTTP/1.1
a;chunk-signature:cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
abcdefjikl\r
c;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
123456789012\r
0;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
\re
"
--- error_log
InvalidRequest:Invalid chunk metadata


=== TEST 8: test Invalid aws chunk data size
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local test_util = require("test_util")
            local data, err_code, err_msg = test_util.test_reader(1, 2)
            if err_code ~= nil then
                ngx.log(ngx.ERR, err_code, ":", err_msg)
                return
            end

            ngx.say(data)
        ';
    }
--- more_headers
x-amz-content-sha256: STREAMING-AWS4-HMAC-SHA256-PAYLOAD
x-amz-decoded-content-length: 22

--- request eval
"PUT /t HTTP/1.1
a;chunk-signature:cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
abcdefjikl\r
c;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
1234569012\r
0;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
\re"
--- error_log
InvalidRequest:Invalid chunk metadata


=== TEST 9: test lost of last chunk
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local test_util = require("test_util")
            local data, err_code, err_msg = test_util.test_reader(nil, 22)
            if err_code ~= nil then
                ngx.log(ngx.ERR, err_code, ":", err_msg)
                return
            end

            ngx.say(data)
        ';
    }
--- more_headers
x-amz-content-sha256: STREAMING-AWS4-HMAC-SHA256-PAYLOAD
x-amz-decoded-content-length: 22

--- request eval
"PUT /t HTTP/1.1
a;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
abcdefjikl\r
c;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
1234569012\r
e"
--- error_log
InvalidRequest:read body error. closed


=== TEST 10: test invalid last chunk
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local test_util = require("test_util")
            local data, err_code, err_msg = test_util.test_reader(1, 2)
            if err_code ~= nil then
                ngx.log(ngx.ERR, err_code, ":", err_msg)
                return
            end

            ngx.say(data)
        ';
    }
--- more_headers
x-amz-content-sha256: STREAMING-AWS4-HMAC-SHA256-PAYLOAD
x-amz-decoded-content-length: 22

--- request eval
"PUT /t HTTP/1.1
a;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
abcdefjikl\r
c;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
123456789012\r
0;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
1\r
e"
--- error_log
InvalidRequest:Invalid chunk end



=== TEST 11: test read block size
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local test_util = require("test_util")
            local opts = {
                block_size = 1024
            }
            local data, err_code, err_msg = test_util.test_reader(1, 2, opts)
            if err_code ~= nil then
                ngx.log(ngx.ERR, err_code, ":", err_msg)
                return
            end

            ngx.say(data)
        ';
    }
--- more_headers
x-amz-content-sha256: STREAMING-AWS4-HMAC-SHA256-PAYLOAD
x-amz-decoded-content-length: 22

--- request eval
"PUT /t HTTP/1.1
a;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
abcdefjikl\r
c;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
123456789012\r
0;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
\r\ne"

--- response_body_like
abcdefjikl123456789012

--- no_error_log
[error]


=== TEST 12: test pre_read body size
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local test_util = require("test_util")
            local opts = {
                block_size = 1024
            }
            local data, err_code, err_msg = test_util.test_reader(1024, 2, opts)
            if err_code ~= nil then
                ngx.log(ngx.ERR, err_code, ":", err_msg)
                return
            end

            ngx.say(data)
        ';
    }
--- more_headers
x-amz-content-sha256: STREAMING-AWS4-HMAC-SHA256-PAYLOAD
x-amz-decoded-content-length: 22

--- request eval
"PUT /t HTTP/1.1
a;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
abcdefjikl\r
c;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
123456789012\r
0;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
\r\ne"

--- response_body_like
abcdefjikl123456789012

--- no_error_log
[error]


=== TEST 13: test read body size
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local test_util = require("test_util")
            local opts = {
                block_size = 1024
            }
            local data, err_code, err_msg = test_util.test_reader(1024, 1025, opts)
            if err_code ~= nil then
                ngx.log(ngx.ERR, err_code, ":", err_msg)
                return
            end

            ngx.say(data)
        ';
    }
--- more_headers
x-amz-content-sha256: STREAMING-AWS4-HMAC-SHA256-PAYLOAD
x-amz-decoded-content-length: 22

--- request eval
"PUT /t HTTP/1.1
a;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
abcdefjikl\r
c;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
123456789012\r
0;chunk-signature=cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628\r
\r\ne"

--- response_body_like
abcdefjikl123456789012

--- no_error_log
[error]


=== TEST 14: test normal body
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local test_util = require("test_util")
            local opts = {
                block_size = 1024
            }
            local data, err_code, err_msg = test_util.test_reader(10, 5, opts)
            if err_code ~= nil then
                ngx.log(ngx.ERR, err_code, ":", err_msg)
                return
            end

            ngx.say(data)
        ';
    }

--- request eval
"PUT /t HTTP/1.1
abcdefjiklafsdjkldfjsljfsklfafslfjj123456789012"

--- response_body_like
abcdefjiklafsdjkldfjsljfsklfafslfjj123456789012

--- no_error_log
[error]


=== TEST 15: test normal body with large content-length
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local test_util = require("test_util")
            local opts = {
                timeout = 2000,
                block_size = 1024,
            }
            local data, err_code, err_msg = test_util.test_reader(10, 35, opts)
            if err_code ~= nil then
                ngx.log(ngx.ERR, err_code, ":", err_msg)
                return
            end

            ngx.say(data)
        ';
    }

--- more_headers
Content-Length:1000

--- request eval
"PUT /t HTTP/1.1
abcdefjiklafsdjkldfjsljfsklfafslfjj123456789012"

--- error_log
RequestTimeout:read body error

--- timeout: 4000
