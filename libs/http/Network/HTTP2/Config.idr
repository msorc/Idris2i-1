||| The settings and limits of HTTP/2 connections (`Network.HTTP2.Connection`),
||| as the server and the client of the library take them.
module Network.HTTP2.Config

%default total

--------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------

||| The settings and limits of the HTTP/2 connections of an endpoint.
||| Times are in milliseconds.
public export
record H2Config where
  constructor MkH2Config
  ||| Serve HTTP/2 with prior knowledge on connections that are not TLS
  ||| (`h2c`: the server recognises the preface of the client).
  cleartext : Bool
  ||| `SETTINGS_MAX_CONCURRENT_STREAMS`: more streams opened by the peer
  ||| at a time are refused (REFUSED_STREAM).
  maxConcurrentStreams : Int
  ||| `SETTINGS_INITIAL_WINDOW_SIZE`: how much of the body of a stream the
  ||| peer may send before the application reads it.
  initialWindowSize : Int
  ||| The window of the whole connection (raised from 65,535 at the start).
  connectionWindowSize : Int
  ||| `SETTINGS_MAX_HEADER_LIST_SIZE`: a larger header list (as RFC 9113
  ||| counts it) is answered with 431 (or reset, on a client).
  maxHeaderListSize : Int
  ||| `SETTINGS_HEADER_TABLE_SIZE` of the decoder.
  headerTableSize : Int
  ||| The most bytes of a header block with its CONTINUATION frames (as
  ||| received, compressed): beyond it, ENHANCE_YOUR_CALM.
  maxHeaderBlockSize : Int
  ||| The most CONTINUATION frames of one header block.
  maxContinuations : Int
  ||| How long the peer has to acknowledge our SETTINGS.
  settingsTimeout : Int
  ||| The most control frames (acknowledgements of SETTINGS and PING,
  ||| RST_STREAM) queued for writing: a peer that makes more and does not
  ||| read them is disconnected (ENHANCE_YOUR_CALM).
  maxQueuedControlFrames : Int
  ||| The most streams that the peer may reset per second while they are
  ||| in progress (the rapid reset of CVE-2023-44487): beyond it,
  ||| ENHANCE_YOUR_CALM.
  maxResetsPerSecond : Int
  ||| The most frames per second that carry nothing (empty DATA without
  ||| END_STREAM, empty CONTINUATION, empty unknown frames): beyond it,
  ||| ENHANCE_YOUR_CALM.
  maxEmptyFramesPerSecond : Int
  ||| The most bytes of a stream queued for the writer: the writer of the
  ||| body of a stream waits beyond it.
  streamBufferSize : Int
  ||| The most bytes of all the streams queued for the writer.
  connectionBufferSize : Int

||| h2c on, 100 streams, windows of 256 KiB per stream and 1 MiB per
||| connection, header lists of 64 KiB, the default table of 4 KiB, header
||| blocks of 128 KiB in at most 64 CONTINUATION frames, 10 s for the
||| settings, 1,000 queued control frames, 200 resets and 1,000 empty
||| frames per second, 256 KiB queued per stream and 2 MiB per connection.
export
defaultH2Config : H2Config
defaultH2Config =
  MkH2Config True 100 262144 1048576 65536 4096 131072 64 10000 1000 200 1000 262144 2097152

||| The protocol identifier of HTTP/2 over TLS, for ALPN.
export
h2Protocol : String
h2Protocol = "h2"

