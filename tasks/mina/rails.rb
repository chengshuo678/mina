require 'mina/deploy'
require 'mina/bundler'

set :rails_env, 'production'
set :bundle_prefix, -> { "RAILS_ENV='#{fetch(:rails_env)}' #{fetch(:bundle_bin)} exec" }
set :rake, -> { "#{fetch(:bundle_prefix)} rake" }
set :rails, -> { "#{fetch(:bundle_prefix)} rails" }
set :compiled_asset_path, 'public/assets'
set :asset_paths, ['vendor/assets/', 'app/assets/']

set :shared_dirs, fetch(:shared_dirs, []).push('log', 'tmp/cache', fetch(:compiled_asset_path))

desc 'Starts an interactive console.'
task console: :environment do
  set :execution_mode, :exec
  in_path "#{fetch(:current_path)}" do
    command "#{fetch(:rails)} console"
  end
end

desc 'Tail log from server'
task log: :environment do
  set :execution_mode, :exec
  in_path "#{fetch(:shared_path)}/log" do
    command "tail -f #{fetch(:rails_env)}.log"
  end
end

namespace :rails do
  desc 'Migrate database'
  task db_migrate: :environment do
    if fetch(:force_migrate)
      comment 'Migrating database'
      command "#{fetch(:rake)} db:migrate"
    else
      command check_for_changes_script(
        at: ['db/migrate'],
        skip: "echo '-----> DB migrations unchanged; skipping DB migration'",
        changed: %(
          echo '-----> Migrating database'
          #{echo_cmd("#{fetch(:rake)} db:migrate")}
        )
      ), quiet: true
    end
  end

  desc 'Create database'
  task db_create: :environment do
    comment 'Creating database'
    command "#{fetch(:rake)} db:create"
  end

  desc 'Rollback database'
  task db_rollback: :environment do
    comment 'Rollbacking database'
    command "#{fetch(:rake)} db:rollback"
  end

  desc 'Precompiles assets (skips if nothing has changed since the last release).'
  task assets_precompile: :environment do
    if fetch(:force_asset_precompile)
      comment 'Precompiling asset files'
      command "#{fetch(:rake)} assets:precompile"
    else
      command check_for_changes_script(
        at: fetch(:asset_paths),
        skip: 'echo "-----> Skipping asset precompilation"',
        changed: %(
          echo "-----> Precompiling asset files"
          #{echo_cmd "#{fetch(:rake)} assets:precompile"}
        )
      ), quiet: true
    end
  end
end

def check_for_changes_script(options)
  diffs = options[:at].map do |path|
    "diff -qrN '#{fetch(:current_path)}/#{path}' './#{path}' 2>/dev/null"
  end.join(' && ')

  %(if #{diffs}
    then
      #{options[:skip]}
    else
      #{options[:changed]}
    fi)
end

# Macro used later by :rails, :rake, etc
make_run_task = lambda { |name, example|
  task name, [:arguments] => :environment do |_, args|
    set :execution_mode, :exec

    arguments = args[:arguments]
    unless arguments
      puts %(You need to provide arguments. Try: mina "#{name}[#{example}]")
      exit 1
    end
    command %(cd "#{deploy_to!}/#{current_path!}" && #{fetch(name)} #{arguments})
  end
}

desc 'Execute a Rails command in the current deploy.'
make_run_task[:rails, 'console']

desc 'Execute a Rake command in the current deploy.'
make_run_task[:rake, 'db:migrate']
