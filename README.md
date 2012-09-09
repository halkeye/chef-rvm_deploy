## Description

This cookbook provides rvm_deploy resource, which can be used just like deploy
or deploy_revision resources, but it provides rvm integration.

## Requirements

## Attributes

## Usage

You can use any attibutes you can use in <a href="http://wiki.opscode.com/display/chef/Deploy+Resource">Deploy</a>
resource, with some additions:

* ruby_string, String, default: nil, example: "ruby-1.9.3-p194@gemset", gemset is optional
* precompile_assets, Boolean, default: true

```ruby
rvm_deploy "/my/deploy/dir" do
  ruby_string "ruby-1.9.3-p194@project"
  precompile_assets true
  repo "git@github.com/whoami/project"
  revision "abc123" # or "HEAD" or "TAG_for_1.0" or (subversion) "1234"
  user "deploy_ninja"
  enable_submodules true
  migrate true
  migration_command "rake db:migrate"
  environment "RAILS_ENV" => "production", "OTHER_ENV" => "foo"
  shallow_clone true
  action :deploy # or :rollback
  restart_command "touch tmp/restart.txt"
  git_ssh_wrapper "wrap-ssh4git.sh"
  scm_provider Chef::Provider::Git # is the default, for svn: Chef::Provider::Subversion
  svn_username "whoami"
  svn_password "supersecret"
end
```
