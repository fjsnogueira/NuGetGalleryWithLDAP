USE [master]
GO
/****** Object:  Database [NuGetGallery]    Script Date: 2013/5/27 10:40:22 ******/
--CREATE DATABASE [NuGetGallery]
-- CONTAINMENT = NONE
-- ON  PRIMARY 
--( NAME = N'NuGetGallery', FILENAME = N'E:\nugetgallery\SQL\NuGetGallery.mdf' , SIZE = 4160KB , MAXSIZE = UNLIMITED, FILEGROWTH = 1024KB )
-- LOG ON 
--( NAME = N'NuGetGallery_log', FILENAME = N'E:\nugetgallery\SQL\NuGetGallery_0.ldf' , SIZE = 1088KB , MAXSIZE = 2048GB , FILEGROWTH = 10%)
--GO
--ALTER DATABASE [NuGetGallery] SET COMPATIBILITY_LEVEL = 110
GO
IF (1 = FULLTEXTSERVICEPROPERTY('IsFullTextInstalled'))
begin
EXEC [NuGetGallery].[dbo].[sp_fulltext_database] @action = 'enable'
end
GO
ALTER DATABASE [NuGetGallery] SET ANSI_NULL_DEFAULT OFF 
GO
ALTER DATABASE [NuGetGallery] SET ANSI_NULLS OFF 
GO
ALTER DATABASE [NuGetGallery] SET ANSI_PADDING OFF 
GO
ALTER DATABASE [NuGetGallery] SET ANSI_WARNINGS OFF 
GO
ALTER DATABASE [NuGetGallery] SET ARITHABORT OFF 
GO
ALTER DATABASE [NuGetGallery] SET AUTO_CLOSE ON 
GO
ALTER DATABASE [NuGetGallery] SET AUTO_CREATE_STATISTICS ON 
GO
ALTER DATABASE [NuGetGallery] SET AUTO_SHRINK OFF 
GO
ALTER DATABASE [NuGetGallery] SET AUTO_UPDATE_STATISTICS ON 
GO
ALTER DATABASE [NuGetGallery] SET CURSOR_CLOSE_ON_COMMIT OFF 
GO
ALTER DATABASE [NuGetGallery] SET CURSOR_DEFAULT  GLOBAL 
GO
ALTER DATABASE [NuGetGallery] SET CONCAT_NULL_YIELDS_NULL OFF 
GO
ALTER DATABASE [NuGetGallery] SET NUMERIC_ROUNDABORT OFF 
GO
ALTER DATABASE [NuGetGallery] SET QUOTED_IDENTIFIER OFF 
GO
ALTER DATABASE [NuGetGallery] SET RECURSIVE_TRIGGERS OFF 
GO
ALTER DATABASE [NuGetGallery] SET  DISABLE_BROKER 
GO
ALTER DATABASE [NuGetGallery] SET AUTO_UPDATE_STATISTICS_ASYNC OFF 
GO
ALTER DATABASE [NuGetGallery] SET DATE_CORRELATION_OPTIMIZATION OFF 
GO
ALTER DATABASE [NuGetGallery] SET TRUSTWORTHY OFF 
GO
ALTER DATABASE [NuGetGallery] SET ALLOW_SNAPSHOT_ISOLATION OFF 
GO
ALTER DATABASE [NuGetGallery] SET PARAMETERIZATION SIMPLE 
GO
ALTER DATABASE [NuGetGallery] SET READ_COMMITTED_SNAPSHOT OFF 
GO
ALTER DATABASE [NuGetGallery] SET HONOR_BROKER_PRIORITY OFF 
GO
ALTER DATABASE [NuGetGallery] SET RECOVERY SIMPLE 
GO
ALTER DATABASE [NuGetGallery] SET  MULTI_USER 
GO
ALTER DATABASE [NuGetGallery] SET PAGE_VERIFY CHECKSUM  
GO
ALTER DATABASE [NuGetGallery] SET DB_CHAINING OFF 
GO
--ALTER DATABASE [NuGetGallery] SET FILESTREAM( NON_TRANSACTED_ACCESS = OFF ) 
GO
--ALTER DATABASE [NuGetGallery] SET TARGET_RECOVERY_TIME = 0 SECONDS 
GO
USE [NuGetGallery]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[AggregateStatistics]
AS
    SET NOCOUNT ON

    DECLARE @mostRecentStatisticsId int
    DECLARE @lastAggregatedStatisticsId int

    SELECT  @mostRecentStatisticsId = MAX([Key]) FROM PackageStatistics
    SELECT  @lastAggregatedStatisticsId = DownloadStatsLastAggregatedId FROM GallerySettings
    SELECT  @lastAggregatedStatisticsId = ISNULL(@lastAggregatedStatisticsId, 0)

    IF (@mostRecentStatisticsId IS NULL)
        RETURN

    DECLARE @DownloadStats TABLE
    (
            PackageKey int PRIMARY KEY
        ,   DownloadCount int
    )

    DECLARE @AffectedPackages TABLE
    (
            PackageRegistrationKey int
    )

    INSERT      @DownloadStats
    SELECT      stats.PackageKey, DownloadCount = COUNT(1)
    FROM        PackageStatistics stats
    WHERE       [Key] > @lastAggregatedStatisticsId
            AND [Key] <= @mostRecentStatisticsId
    GROUP BY    stats.PackageKey

    BEGIN TRANSACTION

        UPDATE      Packages
        SET         Packages.DownloadCount = Packages.DownloadCount + stats.DownloadCount,
					Packages.LastUpdated = GetUtcDate()
        OUTPUT      inserted.PackageRegistrationKey INTO @AffectedPackages
        FROM        Packages
        INNER JOIN  @DownloadStats stats ON Packages.[Key] = stats.PackageKey        
        
        UPDATE      PackageRegistrations
        SET         DownloadCount = TotalDownloadCount
        FROM        (
                    SELECT      Packages.PackageRegistrationKey
                            ,   SUM(Packages.DownloadCount) AS TotalDownloadCount
                    FROM        (SELECT DISTINCT PackageRegistrationKey FROM @AffectedPackages) affected
                    INNER JOIN  Packages ON Packages.PackageRegistrationKey = affected.PackageRegistrationKey
                    GROUP BY    Packages.PackageRegistrationKey
                    ) AffectedPackageRegistrations
        INNER JOIN  PackageRegistrations ON PackageRegistrations.[Key] = AffectedPackageRegistrations.PackageRegistrationKey
                
        UPDATE      GallerySettings
        SET         DownloadStatsLastAggregatedId = @mostRecentStatisticsId
				,	TotalDownloadCount = (SELECT SUM(DownloadCount) FROM PackageRegistrations)

    COMMIT TRANSACTION


GO
/****** Object:  StoredProcedure [dbo].[ELMAH_GetErrorsXml]    Script Date: 2013/5/27 10:40:22 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[ELMAH_GetErrorsXml]
(
    @Application NVARCHAR(60),
    @PageIndex INT = 0,
    @PageSize INT = 15,
    @TotalCount INT OUTPUT
)
AS 

    SET NOCOUNT ON

    DECLARE @FirstTimeUTC DATETIME
    DECLARE @FirstSequence INT
    DECLARE @StartRow INT
    DECLARE @StartRowIndex INT

    SELECT 
        @TotalCount = COUNT(1) 
    FROM 
        [ELMAH_Error]
    WHERE 
        [Application] = @Application

    -- Get the ID of the first error for the requested page

    SET @StartRowIndex = @PageIndex * @PageSize + 1

    IF @StartRowIndex <= @TotalCount
    BEGIN

        SET ROWCOUNT @StartRowIndex

        SELECT  
            @FirstTimeUTC = [TimeUtc],
            @FirstSequence = [Sequence]
        FROM 
            [ELMAH_Error]
        WHERE   
            [Application] = @Application
        ORDER BY 
            [TimeUtc] DESC, 
            [Sequence] DESC

    END
    ELSE
    BEGIN

        SET @PageSize = 0

    END

    -- Now set the row count to the requested page size and get
    -- all records below it for the pertaining application.

    SET ROWCOUNT @PageSize

    SELECT 
        errorId     = [ErrorId], 
        application = [Application],
        host        = [Host], 
        type        = [Type],
        source      = [Source],
        message     = [Message],
        [user]      = [User],
        statusCode  = [StatusCode], 
        time        = CONVERT(VARCHAR(50), [TimeUtc], 126) + 'Z'
    FROM 
        [ELMAH_Error] error
    WHERE
        [Application] = @Application
    AND
        [TimeUtc] <= @FirstTimeUTC
    AND 
        [Sequence] <= @FirstSequence
    ORDER BY
        [TimeUtc] DESC, 
        [Sequence] DESC
    FOR
        XML AUTO



GO
/****** Object:  StoredProcedure [dbo].[ELMAH_GetErrorXml]    Script Date: 2013/5/27 10:40:22 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[ELMAH_GetErrorXml]
(
    @Application NVARCHAR(60),
    @ErrorId UNIQUEIDENTIFIER
)
AS

    SET NOCOUNT ON

    SELECT 
        [AllXml]
    FROM 
        [ELMAH_Error]
    WHERE
        [ErrorId] = @ErrorId
    AND
        [Application] = @Application



GO
/****** Object:  StoredProcedure [dbo].[ELMAH_LogError]    Script Date: 2013/5/27 10:40:22 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[ELMAH_LogError]
(
    @ErrorId UNIQUEIDENTIFIER,
    @Application NVARCHAR(60),
    @Host NVARCHAR(30),
    @Type NVARCHAR(100),
    @Source NVARCHAR(60),
    @Message NVARCHAR(500),
    @User NVARCHAR(50),
    @AllXml NVARCHAR(MAX),
    @StatusCode INT,
    @TimeUtc DATETIME
)
AS

    SET NOCOUNT ON

    INSERT
    INTO
        [ELMAH_Error]
        (
            [ErrorId],
            [Application],
            [Host],
            [Type],
            [Source],
            [Message],
            [User],
            [AllXml],
            [StatusCode],
            [TimeUtc]
        )
    VALUES
        (
            @ErrorId,
            @Application,
            @Host,
            @Type,
            @Source,
            @Message,
            @User,
            @AllXml,
            @StatusCode,
            @TimeUtc
        )



GO
/****** Object:  Table [dbo].[CuratedFeedManagers]    Script Date: 2013/5/27 10:40:22 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[CuratedFeedManagers](
	[CuratedFeedKey] [int] NOT NULL,
	[UserKey] [int] NOT NULL,
 CONSTRAINT [PK_CuratedFeedManagers] PRIMARY KEY CLUSTERED 
(
	[CuratedFeedKey] ASC,
	[UserKey] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[CuratedFeeds]    Script Date: 2013/5/27 10:40:22 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[CuratedFeeds](
	[Key] [int] IDENTITY(1,1) NOT NULL,
	[Name] [nvarchar](max) NULL,
 CONSTRAINT [PK_CuratedFeeds] PRIMARY KEY CLUSTERED 
(
	[Key] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
/****** Object:  Table [dbo].[CuratedPackages]    Script Date: 2013/5/27 10:40:22 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[CuratedPackages](
	[Key] [int] IDENTITY(1,1) NOT NULL,
	[CuratedFeedKey] [int] NOT NULL,
	[Notes] [nvarchar](max) NULL,
	[PackageRegistrationKey] [int] NOT NULL,
	[AutomaticallyCurated] [bit] NOT NULL,
	[Included] [bit] NOT NULL,
 CONSTRAINT [PK_CuratedPackages] PRIMARY KEY CLUSTERED 
(
	[Key] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
/****** Object:  Table [dbo].[ELMAH_Error]    Script Date: 2013/5/27 10:40:22 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[ELMAH_Error](
	[ErrorId] [uniqueidentifier] NOT NULL,
	[Application] [nvarchar](60) NOT NULL,
	[Host] [nvarchar](50) NOT NULL,
	[Type] [nvarchar](100) NOT NULL,
	[Source] [nvarchar](60) NOT NULL,
	[Message] [nvarchar](500) NOT NULL,
	[User] [nvarchar](50) NOT NULL,
	[StatusCode] [int] NOT NULL,
	[TimeUtc] [datetime] NOT NULL,
	[Sequence] [int] IDENTITY(1,1) NOT NULL,
	[AllXml] [nvarchar](max) NOT NULL,
 CONSTRAINT [PK_ELMAH_Error] PRIMARY KEY CLUSTERED 
(
	[ErrorId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
/****** Object:  Table [dbo].[EmailMessages]    Script Date: 2013/5/27 10:40:22 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[EmailMessages](
	[Key] [int] IDENTITY(1,1) NOT NULL,
	[Body] [nvarchar](max) NULL,
	[FromUserKey] [int] NULL,
	[Sent] [bit] NOT NULL,
	[Subject] [nvarchar](max) NULL,
	[ToUserKey] [int] NOT NULL,
 CONSTRAINT [PK_EmailMessages] PRIMARY KEY CLUSTERED 
(
	[Key] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
/****** Object:  Table [dbo].[GallerySettings]    Script Date: 2013/5/27 10:40:22 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[GallerySettings](
	[Key] [int] IDENTITY(1,1) NOT NULL,
	[DownloadStatsLastAggregatedId] [int] NULL,
	[TotalDownloadCount] [bigint] NULL,
 CONSTRAINT [PK_GallerySettings] PRIMARY KEY CLUSTERED 
(
	[Key] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[PackageAuthors]    Script Date: 2013/5/27 10:40:22 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[PackageAuthors](
	[Key] [int] IDENTITY(1,1) NOT NULL,
	[PackageKey] [int] NOT NULL,
	[Name] [nvarchar](max) NULL,
 CONSTRAINT [PK_PackageAuthors] PRIMARY KEY CLUSTERED 
(
	[Key] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
/****** Object:  Table [dbo].[PackageDependencies]    Script Date: 2013/5/27 10:40:22 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[PackageDependencies](
	[Key] [int] IDENTITY(1,1) NOT NULL,
	[PackageKey] [int] NOT NULL,
	[Id] [nvarchar](128) NULL,
	[VersionSpec] [nvarchar](256) NULL,
	[TargetFramework] [nvarchar](256) NULL,
 CONSTRAINT [PK_PackageDependencies] PRIMARY KEY CLUSTERED 
(
	[Key] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[PackageFrameworks]    Script Date: 2013/5/27 10:40:22 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[PackageFrameworks](
	[Key] [int] IDENTITY(1,1) NOT NULL,
	[TargetFramework] [nvarchar](256) NULL,
	[Package_Key] [int] NULL,
 CONSTRAINT [PK_PackageFrameworks] PRIMARY KEY CLUSTERED 
(
	[Key] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[PackageOwnerRequests]    Script Date: 2013/5/27 10:40:22 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[PackageOwnerRequests](
	[Key] [int] IDENTITY(1,1) NOT NULL,
	[PackageRegistrationKey] [int] NOT NULL,
	[NewOwnerKey] [int] NOT NULL,
	[RequestingOwnerKey] [int] NOT NULL,
	[ConfirmationCode] [nvarchar](max) NULL,
	[RequestDate] [datetime] NOT NULL,
 CONSTRAINT [PK_PackageOwnerRequests] PRIMARY KEY CLUSTERED 
(
	[Key] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
/****** Object:  Table [dbo].[PackageRegistrationOwners]    Script Date: 2013/5/27 10:40:22 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[PackageRegistrationOwners](
	[PackageRegistrationKey] [int] NOT NULL,
	[UserKey] [int] NOT NULL,
 CONSTRAINT [PK_PackageRegistrationOwners] PRIMARY KEY CLUSTERED 
(
	[PackageRegistrationKey] ASC,
	[UserKey] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[PackageRegistrations]    Script Date: 2013/5/27 10:40:22 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[PackageRegistrations](
	[Key] [int] IDENTITY(1,1) NOT NULL,
	[Id] [nvarchar](128) NOT NULL,
	[DownloadCount] [int] NOT NULL,
 CONSTRAINT [PK_PackageRegistrations] PRIMARY KEY CLUSTERED 
(
	[Key] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[Packages]    Script Date: 2013/5/27 10:40:22 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[Packages](
	[Key] [int] IDENTITY(1,1) NOT NULL,
	[PackageRegistrationKey] [int] NOT NULL,
	[Copyright] [nvarchar](max) NULL,
	[Created] [datetime] NOT NULL,
	[Description] [nvarchar](max) NULL,
	[DownloadCount] [int] NOT NULL,
	[ExternalPackageUrl] [nvarchar](max) NULL,
	[HashAlgorithm] [nvarchar](10) NULL,
	[Hash] [nvarchar](256) NOT NULL,
	[IconUrl] [nvarchar](max) NULL,
	[IsLatest] [bit] NOT NULL,
	[LastUpdated] [datetime] NOT NULL,
	[LicenseUrl] [nvarchar](max) NULL,
	[Published] [datetime] NOT NULL,
	[PackageFileSize] [bigint] NOT NULL,
	[ProjectUrl] [nvarchar](max) NULL,
	[RequiresLicenseAcceptance] [bit] NOT NULL,
	[Summary] [nvarchar](max) NULL,
	[Tags] [nvarchar](max) NULL,
	[Title] [nvarchar](256) NULL,
	[Version] [nvarchar](64) NOT NULL,
	[FlattenedAuthors] [nvarchar](max) NULL,
	[FlattenedDependencies] [nvarchar](max) NULL,
	[IsLatestStable] [bit] NOT NULL,
	[Listed] [bit] NOT NULL,
	[IsPrerelease] [bit] NOT NULL,
	[ReleaseNotes] [nvarchar](max) NULL,
	[Language] [nvarchar](20) NULL,
	[MinClientVersion] [nvarchar](44) NULL,
 CONSTRAINT [PK_Packages] PRIMARY KEY CLUSTERED 
(
	[Key] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
/****** Object:  Table [dbo].[PackageStatistics]    Script Date: 2013/5/27 10:40:22 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[PackageStatistics](
	[Key] [int] IDENTITY(1,1) NOT NULL,
	[PackageKey] [int] NOT NULL,
	[Timestamp] [datetime] NOT NULL,
	[IPAddress] [nvarchar](max) NULL,
	[UserAgent] [nvarchar](max) NULL,
	[Operation] [nvarchar](16) NULL,
 CONSTRAINT [PK_PackageStatistics] PRIMARY KEY CLUSTERED 
(
	[Key] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
/****** Object:  Table [dbo].[Roles]    Script Date: 2013/5/27 10:40:22 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[Roles](
	[Key] [int] IDENTITY(1,1) NOT NULL,
	[Name] [nvarchar](max) NULL,
 CONSTRAINT [PK_Roles] PRIMARY KEY CLUSTERED 
(
	[Key] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
/****** Object:  Table [dbo].[UserRoles]    Script Date: 2013/5/27 10:40:22 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[UserRoles](
	[UserKey] [int] NOT NULL,
	[RoleKey] [int] NOT NULL,
 CONSTRAINT [PK_UserRoles] PRIMARY KEY CLUSTERED 
(
	[UserKey] ASC,
	[RoleKey] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

insert into dbo.Roles values('Admins');
    
GO
/****** Object:  Table [dbo].[Users]    Script Date: 2013/5/27 10:40:22 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[Users](
	[Key] [int] IDENTITY(1,1) NOT NULL,
	[ApiKey] [uniqueidentifier] NOT NULL,
	[EmailAddress] [nvarchar](256) NULL,
	[UnconfirmedEmailAddress] [nvarchar](256) NULL,
	[HashedPassword] [nvarchar](256) NULL,
	[Username] [nvarchar](64) NOT NULL,
	[EmailAllowed] [bit] NOT NULL,
	[EmailConfirmationToken] [nvarchar](32) NULL,
	[PasswordResetToken] [nvarchar](32) NULL,
	[PasswordResetTokenExpirationDate] [datetime] NULL,
	[PasswordHashAlgorithm] [nvarchar](max) NOT NULL,
	[DisplayName] [nvarchar](50) NULL,
 CONSTRAINT [PK_Users] PRIMARY KEY CLUSTERED 
(
	[Key] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
/****** Object:  Index [IX_CuratedFeedKey]    Script Date: 2013/5/27 10:40:22 ******/
CREATE NONCLUSTERED INDEX [IX_CuratedFeedKey] ON [dbo].[CuratedFeedManagers]
(
	[CuratedFeedKey] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
/****** Object:  Index [IX_UserKey]    Script Date: 2013/5/27 10:40:22 ******/
CREATE NONCLUSTERED INDEX [IX_UserKey] ON [dbo].[CuratedFeedManagers]
(
	[UserKey] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
/****** Object:  Index [IX_CuratedFeedKey]    Script Date: 2013/5/27 10:40:22 ******/
CREATE NONCLUSTERED INDEX [IX_CuratedFeedKey] ON [dbo].[CuratedPackages]
(
	[CuratedFeedKey] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
/****** Object:  Index [IX_PackageRegistrationKey]    Script Date: 2013/5/27 10:40:22 ******/
CREATE NONCLUSTERED INDEX [IX_PackageRegistrationKey] ON [dbo].[CuratedPackages]
(
	[PackageRegistrationKey] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
SET ANSI_PADDING ON

GO
/****** Object:  Index [IX_ELMAH_Error_App_Time_Seq]    Script Date: 2013/5/27 10:40:22 ******/
CREATE NONCLUSTERED INDEX [IX_ELMAH_Error_App_Time_Seq] ON [dbo].[ELMAH_Error]
(
	[Application] ASC,
	[TimeUtc] DESC,
	[Sequence] DESC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
SET ANSI_PADDING ON

GO
/****** Object:  Index [IX_PackageAuthors_PackageKey]    Script Date: 2013/5/27 10:40:22 ******/
CREATE NONCLUSTERED INDEX [IX_PackageAuthors_PackageKey] ON [dbo].[PackageAuthors]
(
	[PackageKey] ASC
)
INCLUDE ( 	[Key],
	[Name]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
/****** Object:  Index [IX_PackageDependencies]    Script Date: 2013/5/27 10:40:22 ******/
CREATE NONCLUSTERED INDEX [IX_PackageDependencies] ON [dbo].[PackageDependencies]
(
	[PackageKey] ASC
)
INCLUDE ( 	[Key]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
/****** Object:  Index [IX_Package_Key]    Script Date: 2013/5/27 10:40:22 ******/
CREATE NONCLUSTERED INDEX [IX_Package_Key] ON [dbo].[PackageFrameworks]
(
	[Package_Key] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
/****** Object:  Index [IX_PackageRegistrationOwners_UserKey]    Script Date: 2013/5/27 10:40:22 ******/
CREATE NONCLUSTERED INDEX [IX_PackageRegistrationOwners_UserKey] ON [dbo].[PackageRegistrationOwners]
(
	[UserKey] ASC
)
INCLUDE ( 	[PackageRegistrationKey]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
SET ANSI_PADDING ON

GO
/****** Object:  Index [IX_PackageRegistration_Id]    Script Date: 2013/5/27 10:40:22 ******/
CREATE UNIQUE NONCLUSTERED INDEX [IX_PackageRegistration_Id] ON [dbo].[PackageRegistrations]
(
	[DownloadCount] DESC,
	[Id] ASC
)
INCLUDE ( 	[Key]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
SET ANSI_PADDING ON

GO
/****** Object:  Index [IX_PackageRegistration_Id_Key]    Script Date: 2013/5/27 10:40:22 ******/
CREATE NONCLUSTERED INDEX [IX_PackageRegistration_Id_Key] ON [dbo].[PackageRegistrations]
(
	[Id] ASC
)
INCLUDE ( 	[Key]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
/****** Object:  Index [IX_Package_IsLatest]    Script Date: 2013/5/27 10:40:22 ******/
CREATE NONCLUSTERED INDEX [IX_Package_IsLatest] ON [dbo].[Packages]
(
	[IsLatest] ASC,
	[Listed] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
/****** Object:  Index [IX_Package_IsLatestStable]    Script Date: 2013/5/27 10:40:22 ******/
CREATE NONCLUSTERED INDEX [IX_Package_IsLatestStable] ON [dbo].[Packages]
(
	[IsLatestStable] ASC,
	[Listed] ASC,
	[IsPrerelease] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
/****** Object:  Index [IX_Package_Listed]    Script Date: 2013/5/27 10:40:22 ******/
CREATE NONCLUSTERED INDEX [IX_Package_Listed] ON [dbo].[Packages]
(
	[Listed] ASC
)
INCLUDE ( 	[PackageRegistrationKey],
	[IsLatest],
	[IsLatestStable]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
SET ANSI_PADDING ON

GO
/****** Object:  Index [IX_Package_Search]    Script Date: 2013/5/27 10:40:22 ******/
CREATE NONCLUSTERED INDEX [IX_Package_Search] ON [dbo].[Packages]
(
	[IsLatestStable] ASC,
	[IsLatest] ASC,
	[Listed] ASC,
	[IsPrerelease] ASC
)
INCLUDE ( 	[Key],
	[PackageRegistrationKey],
	[Description],
	[Summary],
	[Tags]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
SET ANSI_PADDING ON

GO
/****** Object:  Index [IX_Package_Version]    Script Date: 2013/5/27 10:40:22 ******/
CREATE UNIQUE NONCLUSTERED INDEX [IX_Package_Version] ON [dbo].[Packages]
(
	[PackageRegistrationKey] ASC,
	[Version] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
/****** Object:  Index [IX_Packages_IsLatestStable]    Script Date: 2013/5/27 10:40:22 ******/
CREATE NONCLUSTERED INDEX [IX_Packages_IsLatestStable] ON [dbo].[Packages]
(
	[IsLatestStable] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
SET ANSI_PADDING ON

GO
/****** Object:  Index [IX_Packages_PackageRegistrationKey]    Script Date: 2013/5/27 10:40:22 ******/
CREATE NONCLUSTERED INDEX [IX_Packages_PackageRegistrationKey] ON [dbo].[Packages]
(
	[PackageRegistrationKey] ASC
)
INCLUDE ( 	[Key],
	[Copyright],
	[Created],
	[Description],
	[DownloadCount],
	[ExternalPackageUrl],
	[HashAlgorithm],
	[Hash],
	[IconUrl],
	[IsLatest],
	[LastUpdated],
	[LicenseUrl],
	[Published],
	[PackageFileSize],
	[ProjectUrl],
	[RequiresLicenseAcceptance],
	[Summary],
	[Tags],
	[Title],
	[Version],
	[FlattenedAuthors],
	[FlattenedDependencies],
	[IsLatestStable],
	[Listed],
	[IsPrerelease],
	[ReleaseNotes]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
SET ANSI_PADDING ON

GO
/****** Object:  Index [IX_UsersByUsername]    Script Date: 2013/5/27 10:40:22 ******/
CREATE UNIQUE NONCLUSTERED INDEX [IX_UsersByUsername] ON [dbo].[Users]
(
	[Username] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
ALTER TABLE [dbo].[CuratedPackages] ADD  DEFAULT ((0)) FOR [PackageRegistrationKey]
GO
ALTER TABLE [dbo].[CuratedPackages] ADD  DEFAULT ((0)) FOR [AutomaticallyCurated]
GO
ALTER TABLE [dbo].[CuratedPackages] ADD  DEFAULT ((0)) FOR [Included]
GO
ALTER TABLE [dbo].[ELMAH_Error] ADD  CONSTRAINT [DF_ELMAH_Error_ErrorId]  DEFAULT (newid()) FOR [ErrorId]
GO
ALTER TABLE [dbo].[PackageRegistrations] ADD  DEFAULT ((0)) FOR [DownloadCount]
GO
ALTER TABLE [dbo].[Packages] ADD  DEFAULT ((0)) FOR [DownloadCount]
GO
ALTER TABLE [dbo].[Packages] ADD  CONSTRAINT [DF_Published]  DEFAULT ('2013-05-07T07:58:55.282Z') FOR [Published]
GO
ALTER TABLE [dbo].[Packages] ADD  DEFAULT ((0)) FOR [IsLatestStable]
GO
ALTER TABLE [dbo].[Packages] ADD  DEFAULT ((0)) FOR [Listed]
GO
ALTER TABLE [dbo].[Packages] ADD  DEFAULT ((0)) FOR [IsPrerelease]
GO
ALTER TABLE [dbo].[PackageStatistics] ADD  CONSTRAINT [DF_PackageStatistics_Timestamp]  DEFAULT (getutcdate()) FOR [Timestamp]
GO
ALTER TABLE [dbo].[Users] ADD  DEFAULT ('SHA1') FOR [PasswordHashAlgorithm]
GO
ALTER TABLE [dbo].[CuratedFeedManagers]  WITH CHECK ADD  CONSTRAINT [FK_CuratedFeedManagers_CuratedFeeds_CuratedFeedKey] FOREIGN KEY([CuratedFeedKey])
REFERENCES [dbo].[CuratedFeeds] ([Key])
ON DELETE CASCADE
GO
ALTER TABLE [dbo].[CuratedFeedManagers] CHECK CONSTRAINT [FK_CuratedFeedManagers_CuratedFeeds_CuratedFeedKey]
GO
ALTER TABLE [dbo].[CuratedFeedManagers]  WITH CHECK ADD  CONSTRAINT [FK_CuratedFeedManagers_Users_UserKey] FOREIGN KEY([UserKey])
REFERENCES [dbo].[Users] ([Key])
ON DELETE CASCADE
GO
ALTER TABLE [dbo].[CuratedFeedManagers] CHECK CONSTRAINT [FK_CuratedFeedManagers_Users_UserKey]
GO
ALTER TABLE [dbo].[CuratedPackages]  WITH CHECK ADD  CONSTRAINT [FK_CuratedPackages_CuratedFeeds_CuratedFeedKey] FOREIGN KEY([CuratedFeedKey])
REFERENCES [dbo].[CuratedFeeds] ([Key])
ON DELETE CASCADE
GO
ALTER TABLE [dbo].[CuratedPackages] CHECK CONSTRAINT [FK_CuratedPackages_CuratedFeeds_CuratedFeedKey]
GO
ALTER TABLE [dbo].[CuratedPackages]  WITH CHECK ADD  CONSTRAINT [FK_CuratedPackages_PackageRegistrations_PackageRegistrationKey] FOREIGN KEY([PackageRegistrationKey])
REFERENCES [dbo].[PackageRegistrations] ([Key])
ON DELETE CASCADE
GO
ALTER TABLE [dbo].[CuratedPackages] CHECK CONSTRAINT [FK_CuratedPackages_PackageRegistrations_PackageRegistrationKey]
GO
ALTER TABLE [dbo].[EmailMessages]  WITH CHECK ADD  CONSTRAINT [FK_EmailMessages_Users_FromUserKey] FOREIGN KEY([FromUserKey])
REFERENCES [dbo].[Users] ([Key])
GO
ALTER TABLE [dbo].[EmailMessages] CHECK CONSTRAINT [FK_EmailMessages_Users_FromUserKey]
GO
ALTER TABLE [dbo].[EmailMessages]  WITH CHECK ADD  CONSTRAINT [FK_EmailMessages_Users_ToUserKey] FOREIGN KEY([ToUserKey])
REFERENCES [dbo].[Users] ([Key])
GO
ALTER TABLE [dbo].[EmailMessages] CHECK CONSTRAINT [FK_EmailMessages_Users_ToUserKey]
GO
ALTER TABLE [dbo].[GallerySettings]  WITH CHECK ADD  CONSTRAINT [FK_GallerySettings_PackageStatistics_DownloadStatsLastAggregatedId] FOREIGN KEY([DownloadStatsLastAggregatedId])
REFERENCES [dbo].[PackageStatistics] ([Key])
GO
ALTER TABLE [dbo].[GallerySettings] CHECK CONSTRAINT [FK_GallerySettings_PackageStatistics_DownloadStatsLastAggregatedId]
GO
ALTER TABLE [dbo].[PackageAuthors]  WITH CHECK ADD  CONSTRAINT [FK_PackageAuthors_Packages_PackageKey] FOREIGN KEY([PackageKey])
REFERENCES [dbo].[Packages] ([Key])
GO
ALTER TABLE [dbo].[PackageAuthors] CHECK CONSTRAINT [FK_PackageAuthors_Packages_PackageKey]
GO
ALTER TABLE [dbo].[PackageDependencies]  WITH CHECK ADD  CONSTRAINT [FK_PackageDependencies_Packages_PackageKey] FOREIGN KEY([PackageKey])
REFERENCES [dbo].[Packages] ([Key])
GO
ALTER TABLE [dbo].[PackageDependencies] CHECK CONSTRAINT [FK_PackageDependencies_Packages_PackageKey]
GO
ALTER TABLE [dbo].[PackageFrameworks]  WITH CHECK ADD  CONSTRAINT [FK_PackageFrameworks_Packages_Package_Key] FOREIGN KEY([Package_Key])
REFERENCES [dbo].[Packages] ([Key])
GO
ALTER TABLE [dbo].[PackageFrameworks] CHECK CONSTRAINT [FK_PackageFrameworks_Packages_Package_Key]
GO
ALTER TABLE [dbo].[PackageOwnerRequests]  WITH CHECK ADD  CONSTRAINT [FK_PackageOwnerRequests_PackageRegistrations_PackageRegistrationKey] FOREIGN KEY([PackageRegistrationKey])
REFERENCES [dbo].[PackageRegistrations] ([Key])
GO
ALTER TABLE [dbo].[PackageOwnerRequests] CHECK CONSTRAINT [FK_PackageOwnerRequests_PackageRegistrations_PackageRegistrationKey]
GO
ALTER TABLE [dbo].[PackageOwnerRequests]  WITH CHECK ADD  CONSTRAINT [FK_PackageOwnerRequests_Users_NewOwnerKey] FOREIGN KEY([NewOwnerKey])
REFERENCES [dbo].[Users] ([Key])
GO
ALTER TABLE [dbo].[PackageOwnerRequests] CHECK CONSTRAINT [FK_PackageOwnerRequests_Users_NewOwnerKey]
GO
ALTER TABLE [dbo].[PackageOwnerRequests]  WITH CHECK ADD  CONSTRAINT [FK_PackageOwnerRequests_Users_RequestingOwnerKey] FOREIGN KEY([RequestingOwnerKey])
REFERENCES [dbo].[Users] ([Key])
GO
ALTER TABLE [dbo].[PackageOwnerRequests] CHECK CONSTRAINT [FK_PackageOwnerRequests_Users_RequestingOwnerKey]
GO
ALTER TABLE [dbo].[PackageRegistrationOwners]  WITH CHECK ADD  CONSTRAINT [FK_PackageRegistrationOwners_PackageRegistrations_PackageRegistrationKey] FOREIGN KEY([PackageRegistrationKey])
REFERENCES [dbo].[PackageRegistrations] ([Key])
GO
ALTER TABLE [dbo].[PackageRegistrationOwners] CHECK CONSTRAINT [FK_PackageRegistrationOwners_PackageRegistrations_PackageRegistrationKey]
GO
ALTER TABLE [dbo].[PackageRegistrationOwners]  WITH CHECK ADD  CONSTRAINT [FK_PackageRegistrationOwners_Users_UserKey] FOREIGN KEY([UserKey])
REFERENCES [dbo].[Users] ([Key])
GO
ALTER TABLE [dbo].[PackageRegistrationOwners] CHECK CONSTRAINT [FK_PackageRegistrationOwners_Users_UserKey]
GO
ALTER TABLE [dbo].[Packages]  WITH CHECK ADD  CONSTRAINT [FK_Packages_PackageRegistrations_PackageRegistrationKey] FOREIGN KEY([PackageRegistrationKey])
REFERENCES [dbo].[PackageRegistrations] ([Key])
GO
ALTER TABLE [dbo].[Packages] CHECK CONSTRAINT [FK_Packages_PackageRegistrations_PackageRegistrationKey]
GO
ALTER TABLE [dbo].[PackageStatistics]  WITH CHECK ADD  CONSTRAINT [FK_PackageStatistics_Packages_PackageKey] FOREIGN KEY([PackageKey])
REFERENCES [dbo].[Packages] ([Key])
GO
ALTER TABLE [dbo].[PackageStatistics] CHECK CONSTRAINT [FK_PackageStatistics_Packages_PackageKey]
GO
ALTER TABLE [dbo].[UserRoles]  WITH CHECK ADD  CONSTRAINT [FK_UserRoles_Roles_RoleKey] FOREIGN KEY([RoleKey])
REFERENCES [dbo].[Roles] ([Key])
GO
ALTER TABLE [dbo].[UserRoles] CHECK CONSTRAINT [FK_UserRoles_Roles_RoleKey]
GO
ALTER TABLE [dbo].[UserRoles]  WITH CHECK ADD  CONSTRAINT [FK_UserRoles_Users_UserKey] FOREIGN KEY([UserKey])
REFERENCES [dbo].[Users] ([Key])
GO
ALTER TABLE [dbo].[UserRoles] CHECK CONSTRAINT [FK_UserRoles_Users_UserKey]
GO
USE [master]
GO
ALTER DATABASE [NuGetGallery] SET  READ_WRITE 
GO
