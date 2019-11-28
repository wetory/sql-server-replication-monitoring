/*  
Title: Replication Health Monitoring - deployment script
Description: Script is creating objects for monitoring of replication subscriptions health state. Very simple solution for sending you emails when some subsciption is not running
	or containing warning because of breaking some threshold.

It is creating following stuff in SQL Server instance:
	- view in distribution database
	- stored procedures in distribution database
	- SQL Agent job in msdb database

Author: Tomas Rybnicky 
Date of last update: 
	v1.0 - 27.11.2019 - added possiblity to set autogrowth for restored database based on model database settings (RestoreDatabase stored procedure)

List of previous revisions:
	v0.1 - 27.11.2018 - Initial solution containing all not necesary scripting from testing and development work
*/
USE [master]
GO
SET NOCOUNT ON
GO

-- declare variables used in script
DECLARE @ScriptVersion			NVARCHAR(16) = '1.0.1'
DECLARE @Version				NUMERIC(18,10)
DECLARE @AlertRecipients		NVARCHAR(512)
DECLARE @DbMailProfile			SYSNAME

-- you can change folowing variables according to your needs
SET @AlertRecipients = '<your email addresses here>'
SET @DbMailProfile	 = '<your database mail profile here>'	


PRINT 'SQL Server Replication Health Monitoring - deployment of solution'
PRINT '-------------------------------------------------------------------------'
----------------------------------------------------------------------------------------
-- checking core requirements
----------------------------------------------------------------------------------------
IF IS_SRVROLEMEMBER('sysadmin') = 0
BEGIN
	RAISERROR('You need to be a member of the sysadmin server role to install the solution.',16,1)
END

SET @Version = CAST(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)),CHARINDEX('.',CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max))) - 1) + '.' + REPLACE(RIGHT(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)), LEN(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max))) - CHARINDEX('.',CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)))),'.','') AS numeric(18,10))
IF @Version < 10 PRINT 'WARNING : You are running pretty old nad not supprted version of SQL Server, using this script on your own risk'

----------------------------------------------------------------------------------------
-- script runtime stuff
----------------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Config') IS NOT NULL DROP TABLE #Config
CREATE TABLE #Config (
	[Name] nvarchar(max),
	[Value] nvarchar(max)
)
INSERT INTO #Config ([Name], [Value]) VALUES('ScriptVersion', @ScriptVersion)
INSERT INTO #Config ([Name], [Value]) VALUES('AlertRecipients', @AlertRecipients)
INSERT INTO #Config ([Name], [Value]) VALUES('DbMailProfile', @DbMailProfile)

----------------------------------------------------------------------------------------
-- creating stuff for SQL Server Replication Monitoring - https://github.com/wetory/SQL-Server-Replication-Monitoring
----------------------------------------------------------------------------------------
USE [distribution]
GO
IF OBJECT_ID('[dbo].[v_ReplicationMonitorData]') IS NOT NULL DROP VIEW [dbo].[v_ReplicationMonitorData]
GO
CREATE VIEW [dbo].[v_ReplicationMonitorData]
AS
WITH Subscribers_CTE (
	PublicationId,
	PublisherServer,
	PublisherDatabase,
	SubscriberServer,
	SubscriberDatabase,
	ReplicationType,
	AgentId
) AS (
	SELECT DISTINCT
		ms.publication_id,
		sp.name,
		ms.publisher_db,
		ss.name,
		ms.subscriber_db,
		ms.subscription_type,
		ms.agent_id
	FROM [distribution].[dbo].[MSsubscriptions] ms
		INNER JOIN [master].[sys].[servers] sp ON ms.publisher_id = sp.server_id
		INNER JOIN [master].[sys].[servers] ss ON ms.subscriber_id = ss.server_id
	WHERE ms.subscriber_db <> 'virtual'
)
SELECT
	s.PublicationId,
	s.AgentId,
	s.PublisherServer,
	s.PublisherDatabase,
	s.SubscriberServer,
	s.SubscriberDatabase,
	s.ReplicationType,
	MAX(md.status) AS ReplicationStatus,
	MAX(md.warning) AS ReplicationWarning,
	SUM(md.cur_latency) AS ReplicationLatency,
	MAX(md.last_distsync) AS LastSync
FROM Subscribers_CTE s
	INNER JOIN [distribution].[dbo].[MSreplication_monitordata] md ON md.publication_id = s.PublicationId AND md.agent_id = s.AgentId
GROUP BY 
	s.PublicationId,
	s.AgentId,
	s.PublisherServer,
	s.PublisherDatabase,
	s.SubscriberServer,
	s.SubscriberDatabase,
	s.ReplicationType
GO
PRINT 'STEP : Created view  [dbo].[v_ReplicationMonitorData] in distribution database.'
GO
IF OBJECT_ID('[dbo].[usp_ReplicationMonitor]') IS NOT NULL DROP PROCEDURE [dbo].[usp_ReplicationMonitor]
GO
CREATE PROCEDURE [dbo].[usp_ReplicationMonitor]
/* 
Purpose: This procedure can be used for regular checking of replication status on distribution server. It is using builtin stored procedure sp_replmonitorhelpsubscription.
	Returning table of subscriptions that are not working properly based on agreed rules. Use output parameter to react accordingly in workflow where called. 
	
Author:	Tomas Rybnicky trybnicky@inwk.com
Date of last update: 
	v1.0 - 27.11.2019 - final state where all functionality tested and ready for production
List of previous revisions:
	v0.1 - 27.11.2019 - initial release of this stored procedure
	
Execution example:
	DECLARE @RiseAlert BIT	
	EXEC [distribution].[dbo].[usp_ReplicationMonitor] @RiseAlert OUTPUT	
	SELECT @RiseAlert
*/
@p_SuppressResults	BIT = 0,		-- set to "1" to prevent returning resultset
@p_RiseAlert		BIT = 0 OUTPUT	-- output parameter indicating problem
AS
BEGIN
	SET NOCOUNT ON	

	-- decision if alert to be risen
	SELECT @p_RiseAlert = COUNT(*) FROM [distribution].[dbo].[v_ReplicationMonitorData]
	WHERE ReplicationWarning <> 0 -- some threshold is broken
		OR ReplicationStatus NOT IN (1, 3, 4) -- 1 = Started, 3 = In progress, 4 = Idle 

	-- result set for reporting
	IF @p_RiseAlert <> 0 AND @p_SuppressResults = 0
	BEGIN
		SELECT
			PublisherServer,
			PublisherDatabase,
			SubscriberServer,
			SubscriberDatabase,
			CASE ReplicationType
				WHEN 0 THEN 'Transactional'
				WHEN 1 THEN 'Snapshot'
				WHEN 2 THEN 'Merge'
			END AS ReplicationType,
			CASE ReplicationStatus
				WHEN 6 THEN 'Failed'
				WHEN 5 THEN 'Retrying'
				WHEN 4 THEN 'Idle'
				WHEN 3 THEN 'In progress'
				WHEN 2 THEN 'Stopped'		
				WHEN 1 THEN 'Started'			
			END AS ReplicationStatus,
			ReplicationLatency,
			LastSync AS LastSync
		FROM v_ReplicationMonitorData
		WHERE ReplicationWarning <> 0 -- some threshold is broken
			OR ReplicationStatus NOT IN (1, 3, 4) -- 1 = Started, 3 = In progress, 4 = Idle 
	END
END
GO
PRINT 'STEP : Created stored procedure [dbo].[usp_ReplicationMonitor] in distribution database.'
GO
USE [msdb]
GO
BEGIN TRANSACTION

-- get/set variable values from internal config table
DECLARE @ReturnCode			INT
DECLARE @ScriptVersion		NVARCHAR(16)
DECLARE @AlertRecipients	VARCHAR(256) 
DECLARE @DbMailProfile		SYSNAME
DECLARE @JobName			NVARCHAR(MAX)
DECLARE @JobDescription		NVARCHAR(MAX)
DECLARE @TempCommandVar		NVARCHAR(MAX)

SET @ReturnCode			= 0
SET @ScriptVersion		= (SELECT [Value] FROM #Config WHERE Name = 'ScriptVersion')
SET @AlertRecipients	= (SELECT [Value] FROM #Config WHERE Name = 'AlertRecipients')
SET @DbMailProfile		= (SELECT [Value] FROM #Config WHERE Name = 'DbMailProfile')
SET @JobName			= 'Warning: Replication Health '
SET @JobDescription		= N'Job runing stored procedure checking status and health of replication subscriptions where actual server used as distribution server. Version ' + @ScriptVersion + '. Created by trybnicky@inwk.com'

-- create job category if not exist
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Replication monitoring' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Replication monitoring'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
END

-- drop job first if exists
IF EXISTS (SELECT job_id FROM msdb.dbo.sysjobs_view WHERE name = @JobName) EXEC msdb.dbo.sp_delete_job @job_name=@JobName, @delete_unused_schedule=1	

-- create SQL Agent job
DECLARE @jobId BINARY(16)
EXEC @ReturnCode = msdb.dbo.sp_add_job @job_name=@JobName, 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=@JobDescription, 
		@category_name=N'Replication monitoring', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

-- add step executing monitoring procedure
SET @TempCommandVar = 'SET NOCOUNT ON
DECLARE @RiseAlert BIT
DECLARE @Subject NVARCHAR(512) = ''' + @JobName + ''' + @@SERVERNAME
DECLARE @Recipients NVARCHAR(512) = ''' + @AlertRecipients + '''

EXEC [distribution].[dbo].[usp_ReplicationMonitor] 1, @RiseAlert OUTPUT

IF @RiseAlert > 0
BEGIN 
	EXEC msdb.dbo.sp_send_dbmail
		@profile_name = ''' + @DbMailProfile + ''',
		@recipients = @Recipients,
		@subject = @Subject,
		@body = ''Some replication requires your attention. Below listed subscriptions are not working properly.
			
		Run EXEC [distribution].[dbo].[usp_ReplicationMonitor] to check actual state
			
		'',
		@query = ''EXEC [distribution].[dbo].[usp_ReplicationMonitor]'',
		@attach_query_result_as_file = 0;		
	PRINT ''Replication problems reported to '' + @Recipients
END
ELSE
BEGIN
	PRINT ''All replication subscriptions are working properly.''
END'
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Run Replication Monitor', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command= @TempCommandVar, 
		@database_name=N'distribution', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO
PRINT 'STEP : SQL Agent job "Warning: Replication Health", it is not scheduled.'
GO
PRINT '-------------------------------------------------------------------------'
PRINT 'SQL Server Replication Health Monitoring - deployed to ' + @@SERVERNAME 