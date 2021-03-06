module Line.Messaging.Webhook.TypesSpec where

import Test.Hspec

import Line.Messaging.Webhook.TypesSpecHelper

import Data.Aeson
import Data.Maybe (isJust)
import Data.Time.Clock (UTCTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Line.Messaging.Webhook.Types
import Line.Messaging.Types (Text(..), Sticker(..), Location(..))
import qualified Data.ByteString.Lazy as BL

fromJSONSpec :: (FromJSON a, Eq a, Show a)
             => [(BL.ByteString, Maybe a)]
             -> SpecWith ()
fromJSONSpec ((raw, result):xs) = do
  let title = if isJust result then "success" else "fail"
  it title $ decode raw `shouldBe` result
  fromJSONSpec xs
fromJSONSpec [] = return ()

datetime :: Integer -> UTCTime
datetime = posixSecondsToUTCTime . (/ 1000) . fromInteger

spec :: Spec
spec = do
  describe "body" $ fromJSONSpec
    [ ( goodBody, Just $ Body [] )
    , ( badBody, Nothing)
    ]

  describe "event source" $ fromJSONSpec
    [ ( goodUser, Just $ User "123" )
    , ( goodGroup, Just $ Group "456" Nothing)
    , ( goodRoom, Just $ Room "789" Nothing)
    , ( goodGroupWithUserId, Just $ Group "456" $ Just "789")
    , ( goodRoomWithUserId, Just $ Room "789" $ Just "456")
    , ( badSource, Nothing )
    ]

  let replyE event a = Just $ Body $ [
        event ( User "U206d25c2ea6bd87c17655609a1c37cb8"
              , datetime 1462629479859
              , "nHuyWiB7yP5Zw52FIkcQobQuGDXCTA"
              , a
              )
        ]
  let nonreplyE event a = Just $ Body $ [
        event ( User "U206d25c2ea6bd87c17655609a1c37cb8"
              , datetime 1462629479859
              , ()
              , a
              )
        ]

  describe "text message event" $ fromJSONSpec
    [ ( goodTextMessage, replyE MessageEvent (TextEM "325708" $ Text "Hello, world") )
    , ( badTextMessage, Nothing )
    ]

  describe "image message event" $ fromJSONSpec
    [ ( goodImageMessage, replyE MessageEvent (ImageEM "325708") )
    , ( badImageMessage, Nothing )
    ]

  describe "video message event" $ fromJSONSpec
    [ ( goodVideoMessage, replyE MessageEvent (VideoEM "325708") )
    , ( badVideoMessage, Nothing )
    ]

  describe "audio message event" $ fromJSONSpec
    [ ( goodAudioMessage, replyE MessageEvent (AudioEM "325708") )
    , ( badAudioMessage, Nothing )
    ]

  describe "file message event" $ fromJSONSpec
    [ ( goodFileMessage, replyE MessageEvent (FileEM "325708" "hello.txt" 1234) )
    , ( badFileMessage, Nothing )
    ]

  describe "location message event" $ fromJSONSpec
    [ ( goodLocationMessage, replyE MessageEvent (LocationEM "325708" $
                                               Location
                                                "my location"
                                                "some address"
                                                35.65910807942215
                                                139.70372892916203) )
    , ( badLocationMessage, Nothing )
    ]

  describe "stcker message event" $ fromJSONSpec
    [ ( goodStickerMessage, replyE MessageEvent (StickerEM "325708" $
                                                 Sticker
                                                  "1"
                                                  "1") )
    , ( badStickerMessage, Nothing )
    ]

  describe "follow event" $ fromJSONSpec
    [ ( goodFollow, replyE FollowEvent () )
    , ( badFollow, Nothing )
    ]

  describe "unfollow event" $ fromJSONSpec
    [ ( goodUnfollow, nonreplyE UnfollowEvent () )
    , ( badUnfollow, Nothing )
    ]

  describe "join event" $ fromJSONSpec
    [ ( goodJoin, Just $ Body $ [
        JoinEvent ( Group "cxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" Nothing
                  , datetime 1462629479859
                  , "nHuyWiB7yP5Zw52FIkcQobQuGDXCTA"
                  , ()
                  )
        ] )
    , ( badJoin, Nothing )
    ]

  describe "leave event" $ fromJSONSpec
    [ ( goodLeave, Just $ Body $ [
          LeaveEvent ( Group "cxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" Nothing
                     , datetime 1462629479859
                     , ()
                     , ()
                     )
          ] )
    , ( badLeave, Nothing )
    ]

  describe "postback event" $ fromJSONSpec
    [ ( goodPostback, replyE PostbackEvent (Postback "action=buyItem&itemId=123123&color=red" Nothing) )
    , ( goodPostbackWithDate, replyE PostbackEvent (Postback "action=buyItem&itemId=123123&color=red" (Just $ PostbackParamsDate "1990-01-01")) )
    , ( goodPostbackWithTime, replyE PostbackEvent (Postback "action=buyItem&itemId=123123&color=red" (Just $ PostbackParamsTime "12:34")) )
    , ( goodPostbackWithDatetime, replyE PostbackEvent (Postback "action=buyItem&itemId=123123&color=red" (Just $ PostbackParamsDatetime "1990-01-01 12:34")) )
    , ( badPostback, Nothing )
    ]

  describe "beacon event" $ fromJSONSpec
    [ ( goodBeacon, replyE BeaconEvent (BeaconEnter "d41d8cd98f" Nothing) )
    , ( goodBeaconLeave, replyE BeaconEvent (BeaconLeave "d41d8cd98f" Nothing) )
    , ( goodBeaconBanner, replyE BeaconEvent (BeaconBanner "d41d8cd98f" Nothing) )
    , ( goodBeaconWithDm, replyE BeaconEvent (BeaconEnter "d41d8cd98f" (Just "i am a direct message.")) )
    , ( badBeacon, Nothing )
    ]
