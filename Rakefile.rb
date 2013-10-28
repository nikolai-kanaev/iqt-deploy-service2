require "rubygems"
#require "bundler"
#Bundler.setup
$: << './'

require 'albacore'
require 'rake/clean'
require 'semver'
require 'nokogiri'

require 'buildscripts/morph'
require 'buildscripts/utils'
require 'buildscripts/paths'
require 'buildscripts/project_details'
require 'buildscripts/environment'

# to get the current version of the project, type 'SemVer.find.to_s' in this rake file.

desc 'generate the shared assembly info'
assemblyinfo :assemblyinfo => ["env:release"] do |asm|
  data = commit_data() #hash + date
  asm.product_name = asm.title = PROJECTS[:peds][:title]
  asm.description = PROJECTS[:peds][:description] + " #{data[0]} - #{data[1]}"
  asm.company_name = PROJECTS[:peds][:company]
  # This is the version number used by framework during build and at runtime to locate, link and load the assemblies. When you add reference to any assembly in your project, it is this version number which gets embedded.
  asm.version = BUILD_VERSION
  # Assembly File Version : This is the version number given to file as in file system. It is displayed by Windows Explorer. Its never used by .NET framework or runtime for referencing.
  asm.file_version = BUILD_VERSION
  asm.custom_attributes :AssemblyInformationalVersion => "#{BUILD_VERSION}", # disposed as product version in explorer
    :CLSCompliantAttribute => false,
    :AssemblyConfiguration => "#{CONFIGURATION}",
    :Guid => PROJECTS[:peds][:guid]
  asm.com_visible = false
  asm.copyright = PROJECTS[:peds][:copyright]
  asm.output_file = File.join(FOLDERS[:src], 'SharedAssemblyInfo.cs')
  asm.namespaces = "System", "System.Reflection", "System.Runtime.InteropServices", "System.Security"
end


desc "build sln file"
msbuild :msbuild do |msb|
  msb.solution   = FILES[:sln]
  msb.properties :Configuration => CONFIGURATION
  msb.targets    :Clean, :Build
end

desc "Publish the web site" #DET FUNKAR JU
msbuild :publish do |msb|
  msb.properties :Configuration => CONFIGURATION
  msb.targets :Clean, :Build
  msb.properties = {
  :webprojectoutputdir=>"c:/temp/outputdir/",
  :outdir => "c:/temp/outputdir/bin/"
  }
  msb.solution = FILES[:sln]
end

morph :app_morph do |m|
  YAML::ENGINE.yamler = "psych"
  settings = YAML.load(File.open(File.join('src', 'Deployment', 'webconfig.yml')))
  m.template = "src/Deployment/web.erb.config"
  m.output = "src/iqt-deploy-service2/Web.config"
  m.settings settings[ENV_TARGET]
end

task :peds_output => [:msbuild] do
  target = File.join(FOLDERS[:binaries], PROJECTS[:peds][:id])
  copy_files FOLDERS[:peds][:out], "*.{svc, config}", target
  CLEAN.include(target)
end

task :add_msdeploy_xml do
  out = FOLDERS[:peds][:out]
  site_name = PROJECTS[:peds][:site_name]
  versionnumber = ENV['VERSION_NUMBER'] = SemVer.find.to_s
  
  File.open(File.join(out, 'systemInfo.xml'), 'w') do |f2|  
	# use "\n" for two lines of text  
	f2.puts %Q{<?xml version="1.0" encoding="utf-8"?>
<systemInfo buildVersion="#{versionnumber}" />
}
  end
end

zip :peds_zip => [:add_msdeploy_xml] do |zip|
  zip.directories_to_zip "c:/temp/outputdir/"
  zip.additional_files = "src/iqt-deploy-service2/bin/Release/systemInfo.xml" #MÅSTE SKRIVAS OM
  zip.output_file = "#{PROJECTS[:peds][:title]}-#{SemVer.find.to_s}.zip"
  zip.output_path = FOLDERS[:binaries]
end

task :write => ["env:release", "env:dev"] do
  puts "FOLDERS[:peds][:out]: #{FOLDERS[:peds][:out]}"
  puts "FOLDERS[:binaries]: #{FOLDERS[:binaries]}"
end

desc 'copying artifact to c: builds folder'
task :copy_artifact do
  FileUtils.cp File.join(FOLDERS[:binaries], "#{PROJECTS[:peds][:title]}-#{SemVer.find.to_s}.zip"), File.join(File.dirname("C:/"), "builds/")
end

desc 'connecting and mapping network drives'
task :map_network_drive do
  system('net use ' + ENV['ENV_DEPLOYNETWORKSHARELOCALNAME'] + ' \\\\' + ENV['ENV_NETWORKSHAREHOST'] + '\temp /user:' + ENV['ENV_NETWORKSHAREUSERNAME'] + ' ' + ENV['ENV_NETWORKSHAREPASSWORD'] + '')
  raise TypeError, 'could not map network drive \\\\' + ENV['ENV_NETWORKSHAREHOST'] + '\\temp' if File.directory?(ENV['ENV_DEPLOYNETWORKSHARELOCALNAME'] + '\\') == false
  puts "connected to '\\\\" + ENV['ENV_NETWORKSHAREHOST'] + "\\temp' as nikkan.SEPITAB01"
 
  system('net use ' + ENV['ENV_BACKUPNETWORKSHARELOCALNAME'] + ' \\\\' + ENV['ENV_NETWORKSHAREHOST'] + '\temp /user:' + ENV['ENV_NETWORKSHAREUSERNAME'] + ' ' + ENV['ENV_NETWORKSHAREPASSWORD'] + '')
  raise TypeError, 'could not map network drive \\\\' + ENV['ENV_NETWORKSHAREHOST'] + '\\temp' if File.directory?(ENV['ENV_BACKUPNETWORKSHARELOCALNAME'] + '\\') == false
  puts "connected to '\\\\" + ENV['ENV_NETWORKSHAREHOST'] + "\\temp' as nikkan.SEPITAB01"
end

desc 'extracts the current deployed version number from systemInfo.xml'
task :find_version_number do
  puts "receiving version number from systemInfo.xml"
  #xml_file = File.join(File.dirname(ENV['ENV_DEPLOYNETWORKSHARELOCALNAME'] + "/"), "/", ENV['ENV_DEPLOYMENTFOLDER'], "/iqt-deploy-service/systemInfo.xml")
  xml_file = File.join(File.dirname(ENV['ENV_DEPLOYNETWORKSHARELOCALNAME']), "iqt-deploy-service", "systemInfo.xml")
  if (FileTest.exist?(xml_file))
    begin
	  f = File.open(xml_file)
      doc = Nokogiri::XML(f)
      node = doc.xpath('//systemInfo')
      ENV['VERSION_NUMBER'] = node.attr('buildVersion')
	  f.close
    rescue
      ENV['VERSION_NUMBER'] = '3232'
    end
  else
    ENV['VERSION_NUMBER'] = '0'
  end
  puts "Current version number is #{ENV['VERSION_NUMBER']}."
end

desc 'zipping the current deployed project copying it to backup folder'
zip :zip_copy_backup do |zip|
  puts "zipping service and moving it to backup folder"
  backupfolder = File.join(File.dirname(ENV['ENV_BACKUPNETWORKSHARELOCALNAME']), "/backups/")
  FileUtils.mkdir backupfolder if File.directory?(backupfolder) == false
  zip.directories_to_zip File.join(File.dirname(ENV['ENV_DEPLOYNETWORKSHARELOCALNAME'] + "/"), "iqt-deploy-service")
  #zip.directories_to_zip File.dirname(ENV['ENV_DEPLOYNETWORKSHARELOCALNAME'] + "/iqt-deploy-service")
  zip.output_file = 'iqt-deploy-service.' + ENV['VERSION_NUMBER'] + '.zip'
  zip.output_path = backupfolder
end

desc 'copying artifact to deployment folder'
task :copy_artifact_for_deployment do
  puts 'copying artifact from teamcity server to deployment folder'
  FileUtils.cp_r(File.join(ENV['ENV_TEAMCITYBUILDPATH'], "#{PROJECTS[:peds][:title]}-#{SemVer.find.to_s}.zip"), File.join(File.dirname(ENV['ENV_DEPLOYNETWORKSHARELOCALNAME'] + "/"), "/", ENV['ENV_DEPLOYMENTFOLDER']), :verbose => true)
end

desc 'deploying the new project'
unzip :deploy_content do |unzip|
  puts "removing previous deployment"
  FileUtils.rm_rf File.join(File.dirname(ENV['ENV_DEPLOYNETWORKSHARELOCALNAME'] + "/"), "/", ENV['ENV_DEPLOYMENTFOLDER'], "/iqt-deploy-service")

  puts "unzipping/deploying source code to project folder"
  unzip.destination = File.join(File.dirname(ENV['ENV_DEPLOYNETWORKSHARELOCALNAME'] + "/"), "/", ENV['ENV_DEPLOYMENTFOLDER'], "/iqt-deploy-service")
  unzip.file = File.join(File.dirname(ENV['ENV_DEPLOYNETWORKSHARELOCALNAME'] + "/"), "/", ENV['ENV_DEPLOYMENTFOLDER'], "/", "#{PROJECTS[:peds][:title]}-#{SemVer.find.to_s}.zip")
end

desc 'removing temp artifact from deployment folder'
task :remove_temp_artifact do
  puts 'removing temp artifact from deployment folder'
  FileUtils.rm_rf File.join(File.dirname(ENV['ENV_DEPLOYNETWORKSHARELOCALNAME'] + "/"), "/", ENV['ENV_DEPLOYMENTFOLDER'], "/", "#{PROJECTS[:peds][:title]}-#{SemVer.find.to_s}.zip")
end

desc 'disconnecting and unmapping network drives'
task :disconnect_network_drive do
  puts File.join "disconnecting from share"
  
  system('net use ' + ENV['ENV_DEPLOYNETWORKSHARELOCALNAME'] + ' /DELETE /Y')
  puts "disconnected from '\\\\" + ENV['ENV_NETWORKSHAREHOST'] + "\\temp'"
  
  system('net use ' + ENV['ENV_BACKUPNETWORKSHARELOCALNAME'] + ' /DELETE /Y')
  puts "disconnected from '\\\\" + ENV['ENV_NETWORKSHAREHOST'] + "\\temp'"
end

task :gittask do
  puts 'adding'
  `git add -A` 
  v = SemVer.find
  if `git tag`.split("\n").include?("#{v.to_s}")
	raise "Version #{v.to_s} has already been released! You cannot release it twice."
  end
  puts 'committing'
  `git commit -am "Released version #{v.to_s}"` 
  puts 'tagging'
  `git tag #{v.to_s}`
  puts 'pushing'
  `git push`
end

task :release => ["env:release", :msbuild, :output, :gittask] # JOBBA VIDARE HÄR
task :output => [:peds_output]
task :deploy_it => [:peds_zip, :copy_artifact, :map_network_drive, :find_version_number, :zip_copy_backup, :copy_artifact_for_deployment, :deploy_content, :remove_temp_artifact, :disconnect_network_drive]
task :default  => ["env:release", :assemblyinfo, :msbuild, :app_morph, :output, :deploy_it, :publish]