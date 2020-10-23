module IHP.FrameworkConfig where
                                 
import ClassyPrelude
import qualified System.Environment as Environment
import System.Directory (getCurrentDirectory)
import IHP.Environment
import Data.String.Conversions (cs)
import qualified System.Directory as Directory
import qualified Data.Text as Text
import qualified System.Process as Process
import Network.Wai (Middleware)
import qualified Network.Wai.Middleware.RequestLogger as RequestLogger (logStdoutDev)
import qualified Web.Cookie as Cookie
import Data.Default (def)
import Data.Time.Clock (NominalDiffTime)
import IHP.Mail.Types
import qualified Control.Monad.Trans.State.Lazy as State
import Data.Maybe (fromJust)
import qualified Data.TMap as TMap
import qualified Data.Typeable as Typeable
import IHP.HaskellSupport hiding (set)

newtype AppHostname = AppHostname Text
newtype AppPort = AppPort Int
newtype BaseUrl = BaseUrl Text

-- | Provides IHP with a middleware to log requests and responses.
--
-- By default this uses the RequestLogger middleware from wai-extra. Take a look at the wai-extra
-- documentation when you want to customize the request logging.
--
-- See https://hackage.haskell.org/package/wai-extra-3.0.29.2/docs/Network-Wai-Middleware-RequestLogger.html
-- 
--
-- Set @requestLoggerMiddleware = \application -> application@ to disable request logging.
newtype RequestLoggerMiddleware = RequestLoggerMiddleware Middleware

-- | Provides the default settings for the session cookie.
--
-- - Max Age: 30 days
-- - Same Site Policy: Lax
-- - HttpOnly (no access through JS)
-- - secure, when baseUrl is a https url
--
-- Override this to set e.g. a custom max age or change the default same site policy.
--
-- __Example: Set max age to 90 days__
-- > sessionCookie = defaultIHPSessionCookie { Cookie.setCookieMaxAge = Just (fromIntegral (60 * 60 * 24 * 90)) }
newtype SessionCookie = SessionCookie Cookie.SetCookie

-- | How long db connection are kept alive inside the connecton pool when they're idle
newtype DBPoolIdleTime = DBPoolIdleTime NominalDiffTime

-- | Max number of db connections the connection pool can open to the database
newtype DBPoolMaxConnections = DBPoolMaxConnections Int

newtype DatabaseUrl = DatabaseUrl ByteString

type ConfigBuilder = State.StateT TMap.TMap IO ()

-- | Puts an option into the current configuration
--
-- In case an option already exists with the same type, it will not be overriden:
-- 
-- > option Production
-- > option Development
-- > findOption @Environment
--
-- This code will return 'Production' as the second call to 'option' is ignored to not override the existing option.
option :: forall option. Typeable option => option -> State.StateT TMap.TMap IO ()
option value = State.modify (\map -> if TMap.member @option map then map else TMap.insert value map)

ihpDefaultConfig :: ConfigBuilder
ihpDefaultConfig = do
    option Development
    option $ AppHostname "localhost"

    port <- liftIO defaultAppPort
    option $ AppPort port

    option $ RequestLoggerMiddleware defaultLoggerMiddleware

    option $ Sendmail

    databaseUrl <- liftIO defaultDatabaseUrl

    option $ DatabaseUrl databaseUrl
    option $ DBPoolIdleTime 60
    option $ DBPoolMaxConnections 20

    (AppPort port) <- findOption @AppPort
    (AppHostname appHostname) <- findOption @AppHostname
    option $ BaseUrl ("http://" <> appHostname <> (if port /= 80 then ":" <> tshow port else ""))

    (BaseUrl currentBaseUrl) <- findOption @BaseUrl
    option $ SessionCookie (defaultIHPSessionCookie currentBaseUrl)

findOption :: forall option. Typeable option => State.StateT TMap.TMap IO option
findOption = do
    options <- State.get
    options
        |> TMap.lookup @option
        |> fromMaybe (error $ "Could not find " <> show (Typeable.typeOf (undefined :: option)))
        |> pure

buildFrameworkConfig :: ConfigBuilder -> IO FrameworkConfig
buildFrameworkConfig appConfig = do
    let resolve = do
            (AppHostname appHostname) <- findOption @AppHostname
            environment <- findOption @Environment
            (AppPort appPort) <- findOption @AppPort
            (BaseUrl baseUrl) <- findOption @BaseUrl
            (RequestLoggerMiddleware requestLoggerMiddleware) <- findOption @RequestLoggerMiddleware
            (SessionCookie sessionCookie) <- findOption @SessionCookie
            mailServer <- findOption @MailServer
            (DBPoolIdleTime dbPoolIdleTime) <- findOption @DBPoolIdleTime
            (DBPoolMaxConnections dbPoolMaxConnections) <- findOption @DBPoolMaxConnections
            (DatabaseUrl databaseUrl) <- findOption @DatabaseUrl
            
            pure FrameworkConfig { .. }

    (frameworkConfig, _) <- State.runStateT (appConfig >> ihpDefaultConfig >> resolve) TMap.empty

    pure frameworkConfig

data FrameworkConfig = FrameworkConfig 
    { appHostname :: Text
    , environment :: Environment
    , appPort :: Int
    , baseUrl :: Text

    -- | Provides IHP with a middleware to log requests and responses.
    --
    -- By default this uses the RequestLogger middleware from wai-extra. Take a look at the wai-extra
    -- documentation when you want to customize the request logging.
    --
    -- See https://hackage.haskell.org/package/wai-extra-3.0.29.2/docs/Network-Wai-Middleware-RequestLogger.html
    -- 
    --
    -- Set @requestLoggerMiddleware = \application -> application@ to disable request logging.
    , requestLoggerMiddleware :: Middleware

    -- | Provides the default settings for the session cookie.
    --
    -- - Max Age: 30 days
    -- - Same Site Policy: Lax
    -- - HttpOnly (no access through JS)
    -- - secure, when baseUrl is a https url
    --
    -- Override this to set e.g. a custom max age or change the default same site policy.
    --
    -- __Example: Set max age to 90 days__
    -- > sessionCookie = defaultIHPSessionCookie { Cookie.setCookieMaxAge = Just (fromIntegral (60 * 60 * 24 * 90)) }
    , sessionCookie :: Cookie.SetCookie

    , mailServer :: MailServer

    , databaseUrl :: ByteString 
    -- | How long db connection are kept alive inside the connecton pool when they're idle
    , dbPoolIdleTime :: NominalDiffTime

    -- | Max number of db connections the connection pool can open to the database
    , dbPoolMaxConnections :: Int
}

-- | Returns the default IHP session cookie configuration. Useful when you want to override the default settings in 'sessionCookie'
defaultIHPSessionCookie :: Text -> Cookie.SetCookie
defaultIHPSessionCookie baseUrl = def
    { Cookie.setCookiePath = Just "/"
    , Cookie.setCookieMaxAge = Just (fromIntegral (60 * 60 * 24 * 30))
    , Cookie.setCookieSameSite = Just Cookie.sameSiteLax
    , Cookie.setCookieHttpOnly = True
    , Cookie.setCookieSecure = "https://" `Text.isPrefixOf` baseUrl
    }

data RootApplication = RootApplication deriving (Eq, Show)

defaultLoggerMiddleware :: Middleware
defaultLoggerMiddleware = RequestLogger.logStdoutDev

defaultPort :: Int
defaultPort = 8000

defaultAppPort :: IO Int
defaultAppPort = do
    portStr <- Environment.lookupEnv "PORT"
    case portStr of
        Just portStr -> pure $ fromMaybe (error "PORT: Invalid value") (readMay portStr)
        Nothing -> pure defaultPort

defaultDatabaseUrl :: IO ByteString
defaultDatabaseUrl = do
    currentDirectory <- getCurrentDirectory
    let defaultDatabaseUrl = "postgresql:///app?host=" <> cs currentDirectory <> "/build/db"
    (Environment.lookupEnv "DATABASE_URL") >>= (pure . maybe defaultDatabaseUrl cs )

-- | Finds the lib
--
-- The location depends on whether the framework is installed through nix
-- or checked out from git inside the current project directory.
--
-- When it's installed with nix, the lib dir is located at @lib/ihp@
-- while the dev server binary is located at @bin/RunDevServer@.
findLibDirectory :: IO Text
findLibDirectory = do
    frameworkMountedLocally <- Directory.doesDirectoryExist "IHP"
    ihpLibSymlinkAvailable <- Directory.doesDirectoryExist "build/ihp-lib"
    if frameworkMountedLocally
        then pure "IHP/lib/IHP/"
        else if ihpLibSymlinkAvailable
            then do
                pure "build/ihp-lib/"
            else do
                binDir <- cs <$> Process.readCreateProcess (Process.shell "dirname $(which RunDevServer)") ""
                pure (Text.strip binDir <> "/../lib/IHP/")
