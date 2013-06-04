[NuGet Gallery]
=======================================================================
This is an implementation of the NuGet Gallery and OData Package Feed. This serves as the back-end and community 
website for the NuGet client. For information about the NuGet clients, visit http://nuget.codeplex.com/

This version is modified on official master branch (commit hash: 20488ec30001b9f69d52a0b16ef796df6a4a09f5).<br>
Official repository address is  https://github.com/NuGet/NuGetGallery.git<br>
Official NuGet Gallery address is http://nuget.org/

Directory instruction
=======================================================================
	.nuget 							#nuget settings
	facts 							#test project
	Scripts							#build scripts
	Scripts/NuGetGallery_DB.sql 	#initial database script
	website							#web project


Changelog 
================================================================================
	1.support ldap users login
	2.forbid LDAP users change password and email address
	3.comment register links on UI 
	4.fix some issues


Deployment
================================================================================
To compile the project, you'll need Visual Studio 2012 or later and PowerShell 2.0. You'll also need to 
[install NuGet](http://docs.nuget.org/docs/start-here/installing-nuget). Also, make sure to install the 
[Windows Azure SDK v1.8 or later](http://www.microsoft.com/windowsazure/sdk/).
To build the project, clone it locally:

    git clone https://msstash.morningstar.com/scm/engr/nugetgallery.git    
    cd NuGetGallery
    run PowerShell as Administrator
    Set-ExecutionPolicy Unrestricted 
    .\Build-Solution.ps1

The `Build-Solution.ps1` script will build the solution, run the facts (unit tests), and update the database (from migrations).

