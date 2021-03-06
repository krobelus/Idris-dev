||| Low-Level C Sockets bindings for Idris. Used by higher-level, cleverer things.
|||
||| Original (C) SimonJF, MIT Licensed, 2014
||| Modified (C) The Idris Community, 2015, 2016
module Network.Socket

%include C "idris_net.h"
%include C "sys/types.h"
%include C "sys/socket.h"
%include C "netdb.h"

-- ------------------------------------------------------------ [ Type Aliases ]

public export
ByteLength : Type
ByteLength = Int

public export
ResultCode : Type
ResultCode = Int

||| Protocol Number.
|||
||| Generally good enough to just set it to 0.
public export
ProtocolNumber : Type
ProtocolNumber = Int

||| SocketError: Error thrown by a socket operation
public export
SocketError : Type
SocketError = Int

||| SocketDescriptor: Native C Socket Descriptor
public export
SocketDescriptor : Type
SocketDescriptor = Int

public export
Port : Type
Port = Int

-- --------------------------------------------------------------- [ Constants ]

||| Backlog used within listen() call -- number of incoming calls
public export
BACKLOG : Int
BACKLOG = 20

-- FIXME: This *must* be pulled in from C
public export
EAGAIN : Int
EAGAIN = 11

-- -------------------------------------------------------------- [ Interfaces ]

export
interface ToCode a where
  toCode : a -> Int

-- --------------------------------------------------------- [ Socket Families ]

||| Socket Families
|||
||| The ones that people might actually use. We're not going to need US
||| Government proprietary ones.
public export
data SocketFamily : Type where
  ||| Unspecified
  AF_UNSPEC : SocketFamily

  ||| IP / UDP etc. IPv4
  AF_INET : SocketFamily

  |||  IP / UDP etc. IPv6
  AF_INET6 : SocketFamily

export
Show SocketFamily where
  show AF_UNSPEC = "AF_UNSPEC"
  show AF_INET   = "AF_INET"
  show AF_INET6  = "AF_INET6"

export
ToCode SocketFamily where
  toCode AF_UNSPEC = 0
  toCode AF_INET   = 2
  toCode AF_INET6  = 10

getSocketFamily : Int -> Maybe SocketFamily
getSocketFamily i =
    Prelude.List.lookup i [ (0, AF_UNSPEC)
                          , (2, AF_INET)
                          , (10, AF_INET6)
                          ]

-- ------------------------------------------------------------ [ Socket Types ]
||| Socket Types.
public export
data SocketType : Type where
  ||| Not a socket, used in certain operations
  NotASocket : SocketType

  ||| TCP
  Stream : SocketType

  ||| UDP
  Datagram : SocketType

  ||| Raw sockets
  RawSocket : SocketType

export
Show SocketType where
  show NotASocket = "Not a socket"
  show Stream     = "Stream"
  show Datagram   = "Datagram"
  show RawSocket  = "Raw"

export
ToCode SocketType where
  toCode NotASocket = 0
  toCode Stream     = 1
  toCode Datagram   = 2
  toCode RawSocket  = 3

-- ---------------------------------------------------------------- [ Pointers ]

data RecvStructPtr = RSPtr Ptr
data RecvfromStructPtr = RFPtr Ptr

export
data BufPtr = BPtr Ptr

export
data SockaddrPtr = SAPtr Ptr

-- --------------------------------------------------------------- [ Addresses ]

||| Network Addresses
public export
data SocketAddress : Type where
  IPv4Addr : Int -> Int -> Int -> Int -> SocketAddress

  ||| Not implemented (yet)
  IPv6Addr : SocketAddress

  Hostname : String -> SocketAddress

  ||| Used when there's a parse error
  InvalidAddress : SocketAddress

export
Show SocketAddress where
  show (IPv4Addr i1 i2 i3 i4) = concat $ Prelude.List.intersperse "." (map show [i1, i2, i3, i4])
  show IPv6Addr               = "NOT IMPLEMENTED YET"
  show (Hostname host)        = host
  show InvalidAddress         = "Invalid"

-- --------------------------------------------------------- [ UDP Information ]

-- TODO: Expand to non-string payloads
export
record UDPRecvData where
  constructor MkUDPRecvData
  remote_addr : SocketAddress
  remote_port : Port
  recv_data   : String
  data_len    : Int

export
record UDPAddrInfo where
  constructor MkUDPAddrInfo
  remote_addr : SocketAddress
  remote_port : Port

-- ---------------------------------------------------------- [ Socket Utilies ]

||| Frees a given pointer
export
sock_free : BufPtr -> IO ()
sock_free (BPtr ptr) = foreign FFI_C "idrnet_free" (Ptr -> IO ()) ptr

export
sockaddr_free : SockaddrPtr -> IO ()
sockaddr_free (SAPtr ptr) = foreign FFI_C "idrnet_free" (Ptr -> IO ()) ptr

||| Allocates an amount of memory given by the ByteLength parameter.
|||
||| Used to allocate a mutable pointer to be given to the Recv functions.
export
sock_alloc : ByteLength -> IO BufPtr
sock_alloc bl = map BPtr $ foreign FFI_C "idrnet_malloc" (Int -> IO Ptr) bl

-- ----------------------------------------------------------------- [ Sockets ]
||| The metadata about a socket
export
record Socket where
  constructor MkSocket
  descriptor     : SocketDescriptor
  family         : SocketFamily
  socketType     : SocketType
  protocolNumber : ProtocolNumber


-- ----------------------------------------------------- [ Network Socket API. ]

||| Creates a UNIX socket with the given family, socket type and protocol
||| number. Returns either a socket or an error.
export
socket : (fam  : SocketFamily)
      -> (ty   : SocketType)
      -> (pnum : ProtocolNumber)
      -> IO (Either SocketError Socket)
socket sf st pn = do
  socket_res <- foreign FFI_C "socket"
                        (Int -> Int -> Int -> IO Int)
                        (toCode sf) (toCode st) pn

  if socket_res == -1
    then map Left getErrno
    else return $ Right (MkSocket socket_res sf st pn)

||| Close a socket
export
close : Socket -> IO ()
close sock = foreign FFI_C "close" (Int -> IO ()) (descriptor sock)

private
saString : (Maybe SocketAddress) -> String
saString (Just sa) = show sa
saString Nothing = ""

||| Binds a socket to the given socket address and port.
||| Returns 0 on success, an error code otherwise.
export
bind : (sock : Socket)
    -> (addr : Maybe SocketAddress)
    -> (port : Port)
    -> IO Int
bind sock addr port = do
  bind_res <- foreign FFI_C "idrnet_bind"
                  (Int -> Int -> Int -> String -> Int -> IO Int)
                  (descriptor sock) (toCode $ family sock)
                  (toCode $ socketType sock) (saString addr) port
  if bind_res == (-1)
    then getErrno
    else return 0

||| Connects to a given address and port.
||| Returns 0 on success, and an error number on error.
export
connect : (sock : Socket)
       -> (addr : SocketAddress)
       -> (port : Port)
       -> IO ResultCode
connect sock addr port = do
  conn_res <- foreign FFI_C "idrnet_connect"
                  (Int -> Int -> Int -> String -> Int -> IO Int)
                  (descriptor sock) (toCode $ family sock) (toCode $ socketType sock) (show addr) port

  if conn_res == (-1)
    then getErrno
    else return 0

||| Listens on a bound socket.
|||
||| @sock The socket to listen on.
export
listen : (sock : Socket) -> IO Int
listen sock = do
  listen_res <- foreign FFI_C "listen" (Int -> Int -> IO Int)
                    (descriptor sock) BACKLOG
  if listen_res == (-1)
    then getErrno
    else return 0

||| Parses a textual representation of an IPv4 address into a SocketAddress
parseIPv4 : String -> SocketAddress
parseIPv4 str =
    case splitted of
      (i1 :: i2 :: i3 :: i4 :: _) => IPv4Addr i1 i2 i3 i4
      otherwise                   => InvalidAddress
  where
    toInt' : String -> Integer
    toInt' = cast

    toInt : String -> Int
    toInt s = fromInteger $ toInt' s

    splitted : List Int
    splitted = map toInt (Prelude.Strings.split (\c => c == '.') str)

||| Retrieves a socket address from a sockaddr pointer
getSockAddr : SockaddrPtr -> IO SocketAddress
getSockAddr (SAPtr ptr) = do
  addr_family_int <- foreign FFI_C "idrnet_sockaddr_family"
                             (Ptr -> IO Int)
                             ptr

  -- ASSUMPTION: Foreign call returns a valid int
  assert_total (case getSocketFamily addr_family_int of
    Just AF_INET => do
      ipv4_addr <- foreign FFI_C "idrnet_sockaddr_ipv4"
                           (Ptr -> IO String)
                           ptr

      return $ parseIPv4 ipv4_addr
    Just AF_INET6 => return IPv6Addr
    Just AF_UNSPEC => return InvalidAddress)

||| Accept a connection on the provided socket.
|||
||| Returns on failure a `SocketError`
||| Returns on success a pairing of:
||| + `Socket`        :: The socket representing the connection.
||| + `SocketAddress` :: The
|||
||| @sock The socket used to establish connection.
export
accept : (sock : Socket)
      -> IO (Either SocketError (Socket, SocketAddress))
accept sock = do

  -- We need a pointer to a sockaddr structure. This is then passed into
  -- idrnet_accept and populated. We can then query it for the SocketAddr and free it.

  sockaddr_ptr <- foreign FFI_C "idrnet_create_sockaddr"
                          (IO Ptr)

  accept_res <- foreign FFI_C "idrnet_accept"
                        (Int -> Ptr -> IO Int)
                        (descriptor sock) sockaddr_ptr
  if accept_res == (-1)
    then map Left getErrno
    else do
      let (MkSocket _ fam ty p_num) = sock
      sockaddr <- getSockAddr (SAPtr sockaddr_ptr)
      sockaddr_free (SAPtr sockaddr_ptr)
      return $ Right ((MkSocket accept_res fam ty p_num), sockaddr)

||| Send data on the specified socket.
|||
||| Returns on failure a `SocketError`.
||| Returns on success the `ResultCode`.
|||
||| @sock The socket on which to send the message.
||| @msg  The data to send.
export
send : (sock : Socket)
    -> (msg  : String)
    -> IO (Either SocketError ResultCode)
send sock dat = do
  send_res <- foreign FFI_C "idrnet_send"
                      (Int -> String -> IO Int)
                      (descriptor sock) dat

  if send_res == (-1)
    then map Left getErrno
    else return $ Right send_res

freeRecvStruct : RecvStructPtr -> IO ()
freeRecvStruct (RSPtr p) =
    foreign FFI_C "idrnet_free_recv_struct"
            (Ptr -> IO ())
            p

||| Utility to extract data.
freeRecvfromStruct : RecvfromStructPtr -> IO ()
freeRecvfromStruct (RFPtr p) =
    foreign FFI_C "idrnet_free_recvfrom_struct"
            (Ptr -> IO ())
            p


||| Receive data on the specified socket.
|||
||| Returns on failure a `SocketError`
||| Returns on success a pairing of:
||| + `String`     :: The payload.
||| + `ResultCode` :: The result of the underlying function.
|||
||| @sock The socket on which to receive the message.
||| @len  How much of the data to send.
export
recv : (sock : Socket)
    -> (len : ByteLength)
    -> IO (Either SocketError (String, ResultCode))
recv sock len = do
  -- Firstly make the request, get some kind of recv structure which
  -- contains the result of the recv and possibly the retrieved payload
  recv_struct_ptr <- foreign FFI_C "idrnet_recv"
                             (Int -> Int -> IO Ptr)
                             (descriptor sock) len
  recv_res <- foreign FFI_C "idrnet_get_recv_res"
                      (Ptr -> IO Int)
                      recv_struct_ptr

  if recv_res == (-1)
    then do
      errno <- getErrno
      freeRecvStruct (RSPtr recv_struct_ptr)
      return $ Left errno
    else
      if recv_res == 0
        then do
           freeRecvStruct (RSPtr recv_struct_ptr)
           return $ Left 0
        else do
           payload <- foreign FFI_C "idrnet_get_recv_payload"
                             (Ptr -> IO String)
                             recv_struct_ptr
           freeRecvStruct (RSPtr recv_struct_ptr)
           return $ Right (payload, recv_res)

||| Sends the data in a given memory location
|||
||| Returns on failure a `SocketError`
||| Returns on success the `ResultCode`
|||
||| @sock The socket on which to send the message.
||| @ptr  The location containing the data to send.
||| @len  How much of the data to send.
sendBuf : (sock : Socket)
       -> (ptr  : BufPtr)
       -> (len  : ByteLength)
       -> IO (Either SocketError ResultCode)
sendBuf sock (BPtr ptr) len = do
  send_res <- foreign FFI_C "idrnet_send_buf"
                      (Int -> Ptr -> Int -> IO Int)
                      (descriptor sock) ptr len

  if send_res == (-1)
   then map Left getErrno
   else return $ Right send_res

||| Receive data from a given memory location.
|||
||| Returns on failure a `SocketError`
||| Returns on success the `ResultCode`
|||
||| @sock The socket on which to receive the message.
||| @ptr  The location containing the data to receive.
||| @len  How much of the data to receive.
recvBuf : (sock : Socket)
       -> (ptr  : BufPtr)
       -> (len  : ByteLength)
       -> IO (Either SocketError ResultCode)
recvBuf sock (BPtr ptr) len = do
  recv_res <- foreign FFI_C "idrnet_recv_buf"
                      (Int -> Ptr -> Int -> IO Int)
                      (descriptor sock) ptr len

  if (recv_res == (-1))
    then map Left getErrno
    else return $ Right recv_res

||| Send a message.
|||
||| Returns on failure a `SocketError`
||| Returns on success the `ResultCode`
|||
||| @sock The socket on which to send the message.
||| @addr Address of the recipient.
||| @port The port on which to send the message.
||| @msg  The message to send.
export
sendTo : (sock : Socket)
      -> (addr : SocketAddress)
      -> (port : Port)
      -> (msg  : String)
      -> IO (Either SocketError ByteLength)
sendTo sock addr p dat = do
  sendto_res <- foreign FFI_C "idrnet_sendto"
                   (Int -> String -> String -> Int -> Int -> IO Int)
                   (descriptor sock) dat (show addr) p (toCode $ family sock)

  if sendto_res == (-1)
    then map Left getErrno
    else return $ Right sendto_res

||| Send a message stored in some buffer.
|||
||| Returns on failure a `SocketError`
||| Returns on success the `ResultCode`
|||
||| @sock The socket on which to send the message.
||| @addr Address of the recipient.
||| @port The port on which to send the message.
||| @ptr  A Pointer to the buffer containing the message.
||| @len  The size of the message.
sendToBuf : (sock : Socket)
         -> (addr : SocketAddress)
         -> (port : Port)
         -> (ptr  : BufPtr)
         -> (len  : ByteLength)
         -> IO (Either SocketError ResultCode)
sendToBuf sock addr p (BPtr dat) len = do
  sendto_res <- foreign FFI_C "idrnet_sendto_buf"
                   (Int -> Ptr -> Int -> String -> Int -> Int -> IO Int)
                   (descriptor sock) dat len (show addr) p (toCode $ family sock)

  if sendto_res == (-1)
    then map Left getErrno
    else return $ Right sendto_res

||| Utility function to get the payload of the sent message as a `String`.
foreignGetRecvfromPayload : RecvfromStructPtr -> IO String
foreignGetRecvfromPayload (RFPtr p) =
  foreign FFI_C "idrnet_get_recvfrom_payload"
                (Ptr -> IO String)
                p

||| Utility function to return senders socket address.
foreignGetRecvfromAddr : RecvfromStructPtr -> IO SocketAddress
foreignGetRecvfromAddr (RFPtr p) = do
  sockaddr_ptr <- map SAPtr $ foreign FFI_C "idrnet_get_recvfrom_sockaddr"
                                      (Ptr -> IO Ptr)
                                      p
  getSockAddr sockaddr_ptr

||| Utility function to return sender's IPV4 port.
foreignGetRecvfromPort : RecvfromStructPtr -> IO Port
foreignGetRecvfromPort (RFPtr p) = do
  sockaddr_ptr <- foreign FFI_C "idrnet_get_recvfrom_sockaddr"
                          (Ptr -> IO Ptr)
                          p
  port         <- foreign FFI_C "idrnet_sockaddr_ipv4_port"
                          (Ptr -> IO Int)
                          sockaddr_ptr
  return port


||| Receive a message.
|||
||| Returns on failure a `SocketError`.
||| Returns on success a triple of
||| + `UDPAddrInfo` :: The address of the sender.
||| + `String`      :: The payload.
||| + `Int`         :: Result value from underlying function.
|||
||| @sock The channel on which to receive.
||| @len  Size of the expected message.
|||
export
recvFrom : (sock : Socket)
        -> (len  : ByteLength)
        -> IO (Either SocketError (UDPAddrInfo, String, ResultCode))
recvFrom sock bl = do
  recv_ptr <- foreign FFI_C "idrnet_recvfrom"
                (Int -> Int -> IO Ptr)
                (descriptor sock) bl

  let recv_ptr' = RFPtr recv_ptr

  if !(nullPtr recv_ptr)
    then map Left getErrno
    else do
      result <- foreign FFI_C "idrnet_get_recvfrom_res"
                        (Ptr -> IO Int)
                        recv_ptr
      if result == -1
        then do
          freeRecvfromStruct recv_ptr'
          map Left getErrno
        else do
          payload <- foreignGetRecvfromPayload recv_ptr'
          port <- foreignGetRecvfromPort recv_ptr'
          addr <- foreignGetRecvfromAddr recv_ptr'
          freeRecvfromStruct recv_ptr'
          return $ Right (MkUDPAddrInfo addr port, payload, result)

||| Receive a message placed on a 'known' buffer.
|||
||| Returns on failure a `SocketError`.
||| Returns on success a pair of
||| + `UDPAddrInfo` :: The address of the sender.
||| + `Int`         :: Result value from underlying function.
|||
||| @sock The channel on which to receive.
||| @ptr  Pointer to the buffer to place the message.
||| @len  Size of the expected message.
|||
recvFromBuf : (sock : Socket)
           -> (ptr  : BufPtr)
           -> (len  : ByteLength)
           -> IO (Either SocketError (UDPAddrInfo, ResultCode))
recvFromBuf sock (BPtr ptr) bl = do
  recv_ptr <- foreign FFI_C "idrnet_recvfrom_buf"
                      (Int -> Ptr -> Int -> IO Ptr)
                      (descriptor sock) ptr bl

  let recv_ptr' = RFPtr recv_ptr

  if !(nullPtr recv_ptr)
    then map Left getErrno
    else do
      result <- foreign FFI_C "idrnet_get_recvfrom_res"
                        (Ptr -> IO Int)
                        recv_ptr
      if result == -1
        then do
          freeRecvfromStruct recv_ptr'
          map Left getErrno
        else do
          port <- foreignGetRecvfromPort recv_ptr'
          addr <- foreignGetRecvfromAddr recv_ptr'
          freeRecvfromStruct recv_ptr'
          return $ Right (MkUDPAddrInfo addr port, result + 1)

-- --------------------------------------------------------------------- [ EOF ]
