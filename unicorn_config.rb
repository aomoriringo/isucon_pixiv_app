worker_processes 32
preload_app true
listen "127.0.0.1:8080"

stderr_path File.expand_path('/var/log/unicorn/err.log', __FILE__)
stdout_path File.expand_path('/var/log/unicorn/out.log', __FILE__)
