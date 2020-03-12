USE [distribution]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[usp_ReplicationMonitor]
/* 
Purpose: This procedure can be used for regular checking of replication status on distribution server. It is using builtin stored procedure sp_replmonitorhelpsubscription.
	Returning table of subscriptions that are not working properly based on agreed rules. Use output parameter @p_RaiseAlert to react accordingly in workflow where called. 
	Output parameter @p_HTMLTableResults can be used for HTML formatted context, you can find HTML table element containing result set in it.
	
Author:	Tomas Rybnicky trybnicky@inwk.com
Date of last update:  
	v1.0.7 - 12.03.2020 - Source for server information changed in view v_ReplicationMonitorData from [sys].[servers] to [dbo].[MSreplservers] in distribution database

List of previous revisions:
	v1.0.6 - 03.02.2020 - Condition for calculating @p_RaiseAlert output variable of usp_ReplicationMonitor procedure changed with static range of replication latency = 500
						- Added script variable for specifying custom name od distribution database
	v1.0.5 - 23.12.2019 - Monitoring refresh data procedure call added to procedure usp_ReplicationMonitor
	v1.0.4 - 16.12.2019 - Log reader agent state checked and added to monitoring procedure results and @p_HTMLTableResults output parameter
	v1.0.3 - 04.12.2019 - replication agent states columns added to view v_ReplicationMonitorData
	v1.0.2 - 04.12.2019 - default value for parameter @p_HTMLTableResults added in stored procedure usp_ReplicationMonitor
	v1.0.1 - 27.11.2019 - added possiblity to set autogrowth for restored database based on model database settings (RestoreDatabase stored procedure)
	v0.0.0 - 27.11.2018 - Initial solution containing all not necesary scripting from testing and development work
	
Execution example:
	DECLARE @RaiseAlert BIT
	DECLARE @ResultTable NVARCHAR(MAX)

	EXEC [distribution].[dbo].[usp_ReplicationMonitor]
		@p_SuppressResults = 1,
		@p_HTMLTableResults = @ResultTable OUTPUT,
		@p_RaiseAlert = @RaiseAlert OUTPUT
*/
@p_SuppressResults		BIT = 0,					-- set to "1" to prevent returning resultset
@p_HTMLTableResults		NVARCHAR(MAX) = '' OUTPUT,	-- output parameter can be formatted as HTML table which is useful for notification emails
@p_RaiseAlert			BIT = 0 OUTPUT				-- output parameter indicating problem
AS
BEGIN
	SET NOCOUNT ON	

	-- call replicaiton monitor refresh data system procedure
	EXEC [sys].[sp_replmonitorrefreshjob] @iterations = 1

	-- decision if alert to be risen
	SELECT @p_RaiseAlert = COUNT(*) FROM [distribution].[dbo].[v_ReplicationMonitorData]
	WHERE (ReplicationWarning <> 0 AND ReplicationLatency > 500)	-- some threshold is broken
		OR ReplicationStatus NOT IN (1, 3, 4)						-- 1 = Started, 3 = In progress, 4 = Idle 
		OR LogReaderAgentState IN (2, 6)							-- 2 = succeeded (means that not running), 6 = failed. Log reader must be in progress or idle

	-- result set for reporting - common resultset
	IF @p_RaiseAlert <> 0 AND @p_SuppressResults = 0
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
			CASE LogReaderAgentState
				WHEN 6 THEN 'Failed'
				WHEN 5 THEN 'Retrying'
				WHEN 4 THEN 'Idle'
				WHEN 3 THEN 'In progress'
				WHEN 2 THEN 'Not running'		
				WHEN 1 THEN 'Started'			
			END AS LogReaderAgentState,
			ReplicationLatency,
			LastSync AS LastSync
		FROM v_ReplicationMonitorData
		WHERE (ReplicationWarning <> 0 AND ReplicationLatency > 500)
			OR ReplicationStatus NOT IN (1, 3, 4)
			OR LogReaderAgentState IN (2, 6)
	END
	
	-- construct HTML table containing results
	IF @p_RaiseAlert <> 0 
	BEGIN
		SET @p_HTMLTableResults = (
			SELECT 
				'<table style="width:100%">'
				+ '<tr>'
				+ '	<th style="text-align:left">PublisherServer</th>' 
				+ '	<th style="text-align:left">PublisherDatabase</th>'
				+ '	<th style="text-align:left">SubscriberServer</th>'
				+ '	<th style="text-align:left">SubscriberDatabase</th>'
				+ '	<th style="text-align:left">ReplicationType</th>'
				+ '	<th style="text-align:left">ReplicationStatus</th>'
				+ '	<th style="text-align:left">LogReaderAgentState</th>'
				+ '	<th style="text-align:left">ReplicationLatency</th>'
				+ '	<th style="text-align:left">LastSync</th>'
				+ '</tr>'
				+ replace( replace( body, '&lt;', '<' ), '&gt;', '>' )
				+ '</table>'
			FROM (
			SELECT CAST( (
				SELECT td = PublisherServer + '</td>'
					+ '<td>' + PublisherDatabase + '</td>' 
					+ '<td>' + SubscriberServer + '</td>'
					+ '<td>' + SubscriberDatabase + '</td>'
					+ '<td>' + ReplicationType + '</td>'
					+ '<td>' + ReplicationStatus + '</td>'
					+ '<td>' + LogReaderAgentState + '</td>'
					+ '<td>' + CAST(ReplicationLatency AS VARCHAR(64)) + '</td>'
					+ '<td>' + CAST(LastSync AS VARCHAR(64))
				FROM (
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
						CASE LogReaderAgentState
							WHEN 6 THEN 'Failed'
							WHEN 5 THEN 'Retrying'
							WHEN 4 THEN 'Idle'
							WHEN 3 THEN 'In progress'
							WHEN 2 THEN 'Not running'		
							WHEN 1 THEN 'Started'			
						END AS LogReaderAgentState,
						ReplicationLatency,
						LastSync AS LastSync
					FROM v_ReplicationMonitorData
					WHERE (ReplicationWarning <> 0 AND ReplicationLatency > 500)
						OR ReplicationStatus NOT IN (1, 3, 4)
						OR LogReaderAgentState IN (2, 6)
					) AS d
				FOR XML PATH( 'tr' ), TYPE ) AS VARCHAR(max) ) AS body
			) AS bodycte
		)
	END
END
