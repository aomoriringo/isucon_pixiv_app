worker_processes 45
preload_app true
listen "/home/isucon/private_isu/webapp/ruby/unicorn.sock", backlog: 1024
pid "/home/isucon/private_isu/webapp/ruby/unicorn.pid"

stderr_path File.expand_path('/var/log/unicorn/err.log', __FILE__)
stdout_path File.expand_path('/var/log/unicorn/out.log', __FILE__)
