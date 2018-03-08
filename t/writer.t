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
            local aws_chunk_writer = require("resty.aws_chunk.writer")

            local chunk_writer = aws_chunk_writer:new()

            local chunk_data = {}
            local datas = {"ab", "cd", "e", ""}

            for _, d in ipairs(datas) do
                table.insert(chunk_data, chunk_writer:make_chunk(d))
            end

            ngx.print(table.concat(chunk_data))
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
