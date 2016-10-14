{-# LANGUAGE DeriveGeneric #-}
module Channels (DiffChannel (..), channels, jobset) where

import Control.Monad (liftM)
import Control.Lens
import GHC.Generics
import Network.Wreq
import Text.HTML.TagSoup (sections, (~==), (~/=), innerText, parseTags)
import Data.Aeson (ToJSON)
import Data.List (isPrefixOf)
import Data.Time.Clock (UTCTime, NominalDiffTime, getCurrentTime, diffUTCTime)
import Data.Time.Format (parseTimeM, defaultTimeLocale)
import Data.Time.LocalTime (localTimeToUTC, hoursToTimeZone)
import Data.Text (pack, unpack, strip)


data Channel = Channel { name :: String
                       , time :: Either String UTCTime
                       } deriving (Show)

data DiffChannel = DiffChannel { dname  :: String
                               , dlabel :: Color
                               , dtime  :: String
                               } deriving (Show, Generic)

instance ToJSON DiffChannel
type Color = String


parseTime :: String -> Either String UTCTime
parseTime = liftM (localTimeToUTC tz) . parseTimeM True defaultTimeLocale format . strip'
  where format = "%F %R"
        tz = hoursToTimeZone 1 -- CET
        strip' = unpack . strip . pack

findGoodChannels :: String -> [Channel]
findGoodChannels = filter isRealdDir . findChannels . parseTags
  where
    isRealdDir channel = not $ "Parent" `isPrefixOf` name channel
    findChannels = map makeChannel . filter isNotHeader . sections (~== "<tr>")
    isNotHeader = (~/= "<th>") . head . drop 1
    makeChannel x = Channel name time
      where name = takeTextOf "<a>" $ x
            time = parseTime . takeTextOf "<td align=\\\"right\\\">" $ x
            takeTextOf t = innerText . take 2 . dropWhile (~/= t)

makeDiffChannel :: Channel -> IO DiffChannel
makeDiffChannel channel = do
  current <- getCurrentTime
  let diff = diffUTCTime current <$> time channel
  return $ DiffChannel (name channel) (diffToLabel diff) (either id humanTimeDiff diff)

-- |The list of the current NixOS channels
channels :: IO [DiffChannel]
channels = do
  r <- get "http://nixos.org/channels/"
  mapM makeDiffChannel $ findGoodChannels $ show $ r ^. responseBody


humanTimeDiff :: NominalDiffTime -> String
humanTimeDiff d
  | days > 1 = doShow days "days"
  | hours > 1 = doShow hours "hours"
  | minutes > 1 = doShow minutes "minutes"
  | otherwise = doShow d "seconds"
  where minutes = d / 60
        hours = minutes / 60
        days = hours / 24
        doShow x unit = (show $ truncate x) ++ " " ++ unit


jobset :: DiffChannel -> Maybe String
jobset channel
 | c == "nixos-unstable"       = Just "nixos/trunk-combined/tested"
 | c == "nixos-unstable-small" = Just "nixos/unstable-small/tested"
 | c == "nixpkgs-unstable"     = Just "nixpkgs/trunk/unstable"
 | "nixos-" `isPrefixOf` c     = Just $ "nixos/release-" ++ (drop 6 c) ++ "/tested"
 | otherwise                   = Nothing
 where
   c = dname channel

-- | Takes time since last update to the channel and colors it based on it's age
diffToLabel :: Either String NominalDiffTime -> Color
diffToLabel (Left _) = ""
diffToLabel (Right time)
  | days < 3 = "success"
  | days < 10 = "warning"
  | otherwise = "danger"
    where days = time / (60 * 60 * 24)
