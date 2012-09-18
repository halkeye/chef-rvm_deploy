class RvmDeployProvider < Chef::Provider::Deploy::Revision
  def symlink
    precompile_assets
    super
  end

  def release_created(release_path)
    super(release_path)
    setup_load_paths
    create_rvmrc
    create_gemset
  end

  def setup_load_paths
    cookbook_file "#{new_resource.shared_path}/config/setup_load_paths.rb" do
      source "setup_load_paths.rb"
      cookbook "rvm_deploy"
      owner new_resource.user
      action :nothing
    end.run_action(:create)

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
        action :nothing
      end.run_action(:create)

      execute "chown gemset to #{user}" do
        command %(chown #{user} -R "#{node[:rvm][:root_path]}/gems/#{ruby_string}")
        action :nothing
      end.run_action(:run)
    end
  end

  def install_gems
    Chef::Log.info "Running bundle install"
    converge_by("Running bundle install") do
      directory "#{new_resource.shared_path}/vendor_bundle" do
        owner new_resource.user
        group new_resource.group
        mode '0755'
        action :nothing
      end.run_action(:create)
      directory "#{release_path}/vendor" do
        owner new_resource.user
        group new_resource.group
        mode '0755'
        action :nothing
      end.run_action(:create)
      link "#{release_path}/vendor/bundle" do
        to "#{new_resource.shared_path}/vendor_bundle"
        action :nothing
      end.run_action(:create)
      common_groups = %w{development test cucumber staging production}
      # common_groups -= [new_resource.environment_name]
      # FIXME
      common_groups -= ["production"]
      common_groups = common_groups.join(' ')

      # Check for a Gemfile.lock
      bundler_deployment = ::File.exists?(::File.join(release_path, "Gemfile.lock"))
       
      Chef::Log.info "bundle install --path=vendor/bundle #{bundler_deployment ? "--deployment " : ""}--without #{common_groups}"

      rvm_shell "install gems" do
        ruby_string new_resource.ruby_string
        cwd release_path
        user new_resource.user
        environment new_resource.environment
        code "bundle install --path=vendor/bundle #{bundler_deployment ? "--deployment " : ""}--without #{common_groups}"
        action :nothing
      end.run_action(:run)
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
      converge_by("precompiling assets") do
        rvm_shell "precompile assets" do
          ruby_string new_resource.ruby_string
          cwd release_path
          user new_resource.user
          code "RAILS_ENV=production bundle exec rake assets:precompile"
          environment new_resource.environment
          action :nothing
        end.run_action(:run)
      end
    end
  end

  def migrate
    run_symlinks_before_migrate

    if @new_resource.migrate
      converge_by("run migrate database ") do
        enforce_ownership

        rvm_shell "migrate database" do
          ruby_string new_resource.ruby_string
          cwd release_path
          user new_resource.user
          code new_resource.migration_command
          environment new_resource.environment
          action :nothing
        end.run_action(:run)
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
      action :nothing
    end.run_action(:run)
  end

end
