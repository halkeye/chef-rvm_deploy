class RvmDeployProvider < Chef::Provider::Deploy::Revision
  def deploy
    enforce_ownership
    verify_directories_exist
    update_cached_repo
    copy_cached_repo
    setup_load_paths
    create_rvmrc
    create_gemset
    install_gems
    enforce_ownership
    callback(:before_migrate, @new_resource.before_migrate)
    migrate
    precompile_assets
    callback(:before_symlink, @new_resource.before_symlink)
    symlink
    callback(:before_restart, @new_resource.before_restart)
    restart
    notify_airbrake
    callback(:after_restart, @new_resource.after_restart)
    cleanup!
    Chef::Log.info "#@new_resource deployed to #{@new_resource.deploy_to}"
  end

  def setup_load_paths
    cookbook_file "#{new_resource.shared_path}/config/setup_load_paths.rb" do
      source "setup_load_paths.rb"
      cookbook "rvm_deploy"
      owner new_resource.user
    end

    new_resource.symlinks["config/setup_load_paths.rb"] = "config/setup_load_paths.rb"
  end

  def create_rvmrc
    file "#{release_path}/.rvmrc" do
      content "rvm use #{new_resource.ruby_string} --create"
      owner new_resource.user
      backup false
      action :nothing
    end.run_action(:create)
  end

  def create_gemset
    user = @new_resource.user
    ruby_string = @new_resource.ruby_string
    ruby_version, gemset = ruby_string.split('@')

    if gemset && !gemset.empty?
      rvm_gemset gemset do
        ruby_string ruby_version
      end

      execute "chown gemset to #{user}" do
        command %(chown #{user} -R "#{node[:rvm][:root_path]}/gems/#{ruby_string}")
      end
    end
  end

  def install_gems
    rvm_shell "install gems" do
      ruby_string new_resource.ruby_string
      cwd release_path
      user new_resource.user
      code "bundle install"
      environment new_resource.environment
    end
  end

  # @see http://jessewolgamott.com/blog/2012/09/03/the-one-where-you-take-your-deploy-to-11-asset-pipeline/
  def paths_changed?(paths)
    changed = true
    if @previous_release_path
      previous_commit_hash = Dir.chdir(@previous_release_path) { `git rev-parse HEAD` }.strip
      Dir.chdir(release_path) do
        if `git log #{previous_commit_hash}..HEAD #{paths.join(' ')}`.empty?
          changed = false
        end
      end
    end
    changed
  end

  def precompile_assets
    if @new_resource.precompile_assets # && paths_changed?(%w(app/assets lib/assets vendor/assets Gemfile.lock config/application.rb))
      rvm_shell "precompile assets" do
        ruby_string new_resource.ruby_string
        cwd release_path
        user new_resource.user
        code "bundle exec rake assets:precompile"
        environment new_resource.environment
      end
    end
  end

  def migrate
    run_symlinks_before_migrate

    if @new_resource.migrate
      enforce_ownership

      rvm_shell "migrate database" do
        ruby_string new_resource.ruby_string
        cwd release_path
        user new_resource.user
        code new_resource.migration_command
        environment new_resource.environment
      end
    end
  end

  def notify_airbrake
    revision = ::File.basename(release_path)
    repository = new_resource.repo
    rvm_shell "notify airbrake" do
      ruby_string new_resource.ruby_string
      cwd release_path
      user new_resource.user
      environment new_resource.environment
      code "bundle exec rake airbrake:deploy TO=#{new_resource.environment['RAILS_ENV']} REVISION='#{revision}' REPO='#{repository}' USER='#{user}'"
      ignore_failure true
    end
  end
end
