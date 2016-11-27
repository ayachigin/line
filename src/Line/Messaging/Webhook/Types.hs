{-|
This module provides types to be used with "Line.Messaging.Webhook".
-}

module Line.Messaging.Webhook.Types (
  -- * Common types
  -- | Re-exported for convenience.
  module Line.Messaging.Common.Types,
  -- * Result and failure
  WebhookResult (..),
  WebhookFailure (..),

  -- * Webhook request body
  -- | The following types and functions are about decoding a webhook request body.

  -- ** Body
  Body (..),
  -- ** Event
  -- | The webhook event data types and the instances for proper type classes
  -- (e.g. 'FromJSON') are implemented here.
  --
  -- For the event spec, please refer to
  -- <https://devdocs.line.me/en/#webhook-event-object the LINE documentation>.
  Event (..),
  EventTuple,
  ReplyToken,
  ReplyableEvent,
  NonReplyableEvent,
  getSource,
  getDatetime,
  getReplyToken,
  getMessage,
  getPostback,
  getBeacon,
  -- *** Event source
  EventSource (..),
  getId,
  -- *** Message event
  EventMessage (..),
  -- *** Beacon event
  BeaconData (..),
  ) where

import Data.Aeson
import Data.Time.Clock (UTCTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Line.Messaging.API.Types
import Line.Messaging.Common.Types
import Network.Wai (Response, Application)
import qualified Data.Text as T

-- | A result type a webhook event handler should return.
--
-- It is eventually transformed to a WAI response or application.
data WebhookResult = Ok -- ^ Respond with an empty 200 OK response.
                   | WaiResponse Response -- ^ Respond with a WAI response.
                   | WaiApp Application -- ^ Respond with a WAI application.

-- | A failure type returned when a webhook request is malformed.
data WebhookFailure = SignatureVerificationFailed -- ^ When the signature is not valid.
                    | MessageDecodeFailed -- ^ When the request body cannot be decoded into defined event types.
                    deriving (Eq, Show)

-- | This type represents a whole request body.
--
-- It is mainly for JSON parsing, and library users may not need to use this
-- type directly.
newtype Body = Body [Event]
             deriving (Eq, Show)

instance FromJSON Body where
  parseJSON (Object v) = Body <$> v .: "events"
  parseJSON _ = fail "Body"

-- | A type to represent each webhook event. The type of an event can be
-- determined with pattern matching.
--
-- @
-- handleEvent :: Event -> IO ()
-- handleEvent (MessageEvent event) = handleMessageEvent event
-- handleEvent (BeaconEvent event) = handleBeaconEvent event
-- handleEvent _ = return ()
--
-- handleMessageEvent :: ReplyableEvent EventMessage -> IO ()
-- handleMessageEvent = undefined
--
-- handleBeaconEvent :: ReplyableEvent BeaconData -> IO ()
-- handleBeaconEvent = undefined
-- @
--
-- All the data contstructors have a type @'EventTuple' r a -> 'Event'@.
data Event = MessageEvent (ReplyableEvent EventMessage)
           | FollowEvent (ReplyableEvent ())
           | UnfollowEvent (NonReplyableEvent ())
           | JoinEvent (ReplyableEvent ())
           | LeaveEvent (NonReplyableEvent ())
           | PostbackEvent (ReplyableEvent Postback)
           | BeaconEvent (ReplyableEvent BeaconData)
           deriving (Eq, Show)

-- | The base type for an event. It is a type alias for 4-tuple containing event
-- data.
--
-- The type variable @r@ is for a reply token, which is @()@ in the case of
-- non-replyable events. The type variable @a@ is a content type, which is
-- @()@ for events without content.
type EventTuple r a = (EventSource, UTCTime, r, a)

-- | A type alias for reply token. It is used by the
-- @<./Line-Messaging-API.html#v:reply reply>@ API.
type ReplyToken = T.Text

-- | This type alias represents a replyable event.
type ReplyableEvent a = EventTuple ReplyToken a
-- | This type alias represents a non-replyable event.
type NonReplyableEvent a = EventTuple () a

-- | Retrieve event source from an event.
getSource :: EventTuple r a -> EventSource
getSource (s, _, _, _) = s

-- | Retrieve datetime when event is sent.
getDatetime :: EventTuple r a -> UTCTime
getDatetime (_, t, _, _) = t

-- | Retrieve a reply token of an event. It can be used only for
-- 'ReplyableEvent'.
getReplyToken :: ReplyableEvent a -> ReplyToken
getReplyToken (_, _, r, _) = r

-- | Retrieve event message from an event. It can be used only for events whose
-- content is a message.
--
-- @
-- handleMessageEvent :: ReplyableEvent EventMessage -> IO ()
-- handleMessageEvent event = do
--   let message = getMessage event
--   print message
-- @
getMessage :: ReplyableEvent EventMessage -> EventMessage
getMessage (_, _, _, m) = m

-- | Retrieve postback data from an event. It can be used only for events whose
-- content is postback data.
--
-- @
-- import qualified Data.Text as T
-- import qualified Data.Text.IO as TIO
--
-- handlePostbackEvent :: ReplyableEvent T.Text -> IO ()
-- handlePostbackEvent event = do
--   let postback = getPostback event
--   TIO.putStrLn postback
-- @
getPostback :: ReplyableEvent Postback -> Postback
getPostback (_, _, _, d) = d

-- | Retrieve beacon data from an event. It can be used only for events whose
-- content is beacon data.
--
-- @
-- handleBeaconEvent :: ReplyableEvent BeaconData -> IO ()
-- handleBeaconEvent event = do
--   let beaconData = getBeacon event
--   print beaconData
-- @
getBeacon :: ReplyableEvent BeaconData -> BeaconData
getBeacon (_, _, _, b) = b

instance FromJSON Event where
  parseJSON (Object v) = v .: "type" >>= \ t ->
    case t :: T.Text of
      "message" -> MessageEvent <$> (replyable v <*> v .: "message")
      "follow" -> FollowEvent <$> (replyable v <*> none)
      "unfollow" -> UnfollowEvent <$> (nonReplyable v <*> none)
      "join" -> JoinEvent <$> (replyable v <*> none)
      "leave" -> LeaveEvent <$> (nonReplyable v <*> none)
      "postback" -> PostbackEvent <$> (replyable v <*> ((v .: "postback") >>= (.: "data")))
      "beacon" -> BeaconEvent <$> (replyable v <*> v .: "beacon")
      _ -> fail "Event"
    where
      common o = (,,,) <$> (o .: "source")
                       <*> (posixSecondsToUTCTime . (/ 1000) . fromInteger <$> o .: "timestamp")
      withReplyToken p o = p <*> o .: "replyToken"
      none = return ()
      replyable o = common o `withReplyToken` o
      nonReplyable o = common o <*> none

  parseJSON _ = fail "Event"

-- | A source from which an event is sent. It can be retrieved with 'getSource'.
data EventSource = User ID
                 | Group ID
                 | Room ID
                 deriving (Eq, Show)

-- | Retrieve identifier from event source
getId :: EventSource -> ID
getId (User i) = i
getId (Group i) = i
getId (Room i) = i

instance FromJSON EventSource where
  parseJSON (Object v) = v .: "type" >>= \ t ->
    case t :: T.Text of
      "user" -> User <$> v .: "userId"
      "group" -> Group <$> v .: "groupId"
      "room" -> Room <$> v .: "roomId"
      _ -> fail "EventSource"
  parseJSON _ = fail "EventSource"

-- | Represent message types sent with 'MessageEvent'. it can be retrieved with
-- 'getMessage'.
--
-- There is no data sent with image, video and audio messages. The actual binary
-- data can be downloaded via the
-- @<./Line-Messaging-API.html#v:getContent getContent>@ API.
--
-- For more details of event messages, please refer to the
-- <https://devdocs.line.me/en/#message-event Message event> section of the LINE
-- documentation.
data EventMessage = TextEM ID Text -- ^ Text event message.
                  | ImageEM ID -- ^ Image event message.
                  | VideoEM ID -- ^ Video event message.
                  | AudioEM ID -- ^ Audio event message.
                  | LocationEM ID Location -- ^ Location event message.
                  | StickerEM ID Sticker -- ^ Sticker event message.
                  deriving (Eq, Show)

instance FromJSON EventMessage where
  parseJSON (Object v) = v .: "type" >>= \ t ->
    case t :: T.Text of
      "text" -> TextEM <$> v .: "id" <*> parseJSON (Object v)
      "image" -> ImageEM <$> v .: "id"
      "video" -> VideoEM <$> v .: "id"
      "audio" -> AudioEM <$> v .: "id"
      "location" -> LocationEM <$> v .: "id" <*> parseJSON (Object v)
      "sticker" -> StickerEM <$> v .: "id" <*> parseJSON (Object v)
      _ -> fail "EventMessage"
  parseJSON _ = fail "IncommingMessage"

-- | Represent beacon data.
data BeaconData = BeaconEnter { getHWID :: ID }
                deriving (Eq, Show)

instance FromJSON BeaconData where
  parseJSON (Object v) = v .: "type" >>= \ t ->
    case t :: T.Text of
      "enter" -> BeaconEnter <$> v .: "hwid"
      _ -> fail "BeaconData"
  parseJSON _ = fail "BeaconData"
