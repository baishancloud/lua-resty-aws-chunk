local _M = {}

_M.fake_signature = 'cc20c730a23e5b260438aa2b13dd64b960e99e06230770ace38265485bd08628'
_M.ptn_chunk_meta = '^(%x+);chunk%-signature=(.+)$'
_M.fmt_chunk_meta = '%x;chunk-signature=%s\r\n'

return _M
