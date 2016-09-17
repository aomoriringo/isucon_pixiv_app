
require 'bundler'
Bundler.require
require 'sinatra/base'
require "sinatra/reloader"
require 'rack-flash'
require 'shellwords'

module Isuconp
  class App < Sinatra::Base
    use Rack::Session::Memcache, autofix_keys: true, secret: ENV['ISUCONP_SESSION_SECRET'] || 'sendagaya'
    use Rack::Flash

    set :public_folder, File.expand_path('../../public', __FILE__)

    UPLOAD_LIMIT = 10 * 1024 * 1024 # 10mb

    POSTS_PER_PAGE = 20

    configure :development do
      require "better_errors"
      require "binding_of_caller"
      require 'rack-lineprof'
      register Sinatra::Reloader
      use BetterErrors::Middleware
      use Rack::Lineprof, profile: 'app.rb'
      BetterErrors.application_root = __dir__
    end

    helpers do
      def config
        @config ||= {
          db: {
            host: ENV['ISUCONP_DB_HOST'] || 'localhost',
            port: ENV['ISUCONP_DB_PORT'] && ENV['ISUCONP_DB_PORT'].to_i,
            username: ENV['ISUCONP_DB_USER'] || 'root',
            password: ENV['ISUCONP_DB_PASSWORD'],
            database: ENV['ISUCONP_DB_NAME'] || 'isuconp',
          },
        }
      end

      def db
        return Thread.current[:isuconp_db] if Thread.current[:isuconp_db]
        client = Mysql2::Client.new(
          host: config[:db][:host],
          port: config[:db][:port],
          username: config[:db][:username],
          password: config[:db][:password],
          database: config[:db][:database],
          encoding: 'utf8mb4',
          reconnect: true,
        )
        client.query_options.merge!(symbolize_keys: true, database_timezone: :local, application_timezone: :local)
        Thread.current[:isuconp_db] = client
        client
      end

      def redis
        return Thread.current[:isuconp_redis] if Thread.current[:isuconp_redis]
        client = Redis.new
        Thread.current[:isuconp_redis] = client
        client
      end

      def db_initialize
        sql = []
        sql << 'DELETE FROM users WHERE id > 1000'
        sql << 'DELETE FROM posts WHERE id > 10000'
        sql << 'DELETE FROM comments WHERE id > 100000'
        sql << 'UPDATE users SET del_flg = 0'
        sql << 'UPDATE users SET del_flg = 1 WHERE id % 50 = 0'
        sql.each do |s|
          db.prepare(s).execute
        end
      end

      def image_initialize
        FileUtils.mv('/home/isucon/private_isu/webapp/public/image/10000.png', '/home/isucon/private_isu/webapp/public/image/10000.png.backup')
        FileUtils.rm(Dir.glob('/home/isucon/private_isu/webapp/public/image/[123456789]????*.???'))
        FileUtils.mv('/home/isucon/private_isu/webapp/public/image/10000.png.backup', '/home/isucon/private_isu/webapp/public/image/10000.png')
      end

      def redis_initialize
        query = <<SQL
SELECT p.id AS id, p.user_id AS user_id, p.body AS body, p.created_at AS created_at, p.ext AS ext, p.account_name AS account_name, u.del_flg AS del_flg
FROM posts p JOIN users u ON p.user_id = u.id
WHERE u.del_flg = 0
ORDER BY p.created_at DESC
LIMIT 100
SQL

        db.query(query).each do |post|
          redis.lpush('index_posts', post[:id])
          redis.hset('index_cache', post[:id], render_index_post({id: post[:id]}))
        end
      end

      def try_login(account_name, password)
        user = db.prepare('SELECT * FROM users WHERE account_name = ? AND del_flg = 0').execute(account_name).first

        if user && calculate_passhash(user[:account_name], password) == user[:passhash]
          return user
        elsif user
          return nil
        else
          return nil
        end
      end

      def validate_user(account_name, password)
        if !(/\A[0-9a-zA-Z_]{3,}\z/.match(account_name) && /\A[0-9a-zA-Z_]{6,}\z/.match(password))
          return false
        end

        return true
      end

      def digest(src)
        # opensslのバージョンによっては (stdin)= というのがつくので取る
        `printf "%s" #{Shellwords.shellescape(src)} | openssl dgst -sha512 | sed 's/^.*= //'`.strip
      end

      def calculate_salt(account_name)
        digest account_name
      end

      def calculate_passhash(account_name, password)
        digest "#{password}:#{calculate_salt(account_name)}"
      end

      def get_session_user()
        if session[:user]
          db.prepare('SELECT * FROM `users` WHERE `id` = ?').execute(
            session[:user][:id]
          ).first
        else
          nil
        end
      end

      def make_posts(results, all_comments: false)
=begin
        posts = []

        results.to_a.each do |post|
          post[:comment_count] = db.prepare('SELECT COUNT(*) AS `count` FROM `comments` WHERE `post_id` = ?').execute(
            post[:id]
          ).first[:count]

          query = 'SELECT * FROM `comments` WHERE `post_id` = ? ORDER BY `created_at` DESC'
          unless all_comments
            query += ' LIMIT 3'
          end
          comments = db.prepare(query).execute(
            post[:id]
          ).to_a
          comments.each do |comment|
            comment[:user] = db.prepare('SELECT * FROM `users` WHERE `id` = ?').execute(
              comment[:user_id]
            ).first
          end
          post[:comments] = comments.reverse

          post[:user] = db.prepare('SELECT * FROM `users` WHERE `id` = ?').execute(
            post[:user_id]
          ).first

          posts.push(post) if post[:user][:del_flg] == 0
          break if posts.length >= POSTS_PER_PAGE
        end

        posts
=end
        results.to_a.each do |result|
          post = result
          post[:comment_count] = db.query("SELECT COUNT(*) AS `count` FROM `comments` WHERE `post_id` = #{result[:id]}").first[:count]

          query = "SELECT `comment`, `account_name` FROM `comments` WHERE `post_id` = #{result[:id]} ORDER BY `created_at` DESC"
          query += ' LIMIT 3' unless all_comments

          post[:comments] = db.query(query)

          post
        end
      end

      def render_index_post(post_detail, new_post=false)

        post = if new_post
                 post_detail
               else
                 post_result = db.query("SELECT `account_name`, `body`, `ext`, `created_at` FROM `posts` WHERE `id` = #{post_detail[:id]}").first

                 post_detail[:account_name] = post_result[:account_name]
                 post_detail[:body] = post_result[:body]
                 post_detail[:ext] = post_result[:ext]
                 post_detail[:created_at] = post_result[:created_at]
                 post_detail[:comments] = db.query("SELECT `comment`, `account_name` FROM `comments` WHERE `post_id` = #{post_detail[:id]} ORDER BY `created_at` DESC LIMIT 3")
                 post_detail[:comment_count] = db.query("SELECT COUNT(*) AS `count` FROM `comments` WHERE `post_id` = #{post_detail[:id]}").first[:count]
                 post_detail
               end

        erb :post_i, locals: { post: post }
      end

      def image_url(post)
        ext = ""
        if post[:ext] == 1
          ext = ".jpg"
        elsif post[:ext] == 2
          ext = ".png"
        elsif post[:ext] == 3
          ext = ".gif"
        end

        "/image/#{post[:id]}#{ext}"
      end
    end

    get '/initialize' do
      db_initialize
      image_initialize
      redis_initialize
      return 200
    end

    get '/login' do
      if get_session_user()
        redirect '/', 302
      end
      erb :login, layout: :layout, locals: { me: nil }
    end

    post '/login' do
      if get_session_user()
        redirect '/', 302
      end

      user = try_login(params['account_name'], params['password'])
      if user
        session[:user] = {
          id: user[:id]
        }
        session[:csrf_token] = SecureRandom.hex(16)
        redirect '/', 302
      else
        flash[:notice] = 'アカウント名かパスワードが間違っています'
        redirect '/login', 302
      end
    end

    get '/register' do
      if get_session_user()
        redirect '/', 302
      end
      erb :register, layout: :layout, locals: { me: nil }
    end

    post '/register' do
      if get_session_user()
        redirect '/', 302
      end

      account_name = params['account_name']
      password = params['password']

      validated = validate_user(account_name, password)
      if !validated
        flash[:notice] = 'アカウント名は3文字以上、パスワードは6文字以上である必要があります'
        redirect '/register', 302
        return
      end

      user = db.prepare('SELECT 1 FROM users WHERE `account_name` = ?').execute(account_name).first
      if user
        flash[:notice] = 'アカウント名がすでに使われています'
        redirect '/register', 302
        return
      end

      query = 'INSERT INTO `users` (`account_name`, `passhash`) VALUES (?,?)'
      db.prepare(query).execute(
        account_name,
        calculate_passhash(account_name, password)
      )

      session[:user] = {
        id: db.last_id
      }
      session[:csrf_token] = SecureRandom.hex(16)
      redirect '/', 302
    end

    get '/logout' do
      session.delete(:user)
      redirect '/', 302
    end

    get '/' do
      me = get_session_user()
=begin
      query = <<SQL
SELECT p.id AS id, p.user_id AS user_id, p.body AS body, p.created_at AS created_at, p.ext AS ext, p.account_name AS account_name, p.del_flg AS del_flg
FROM posts p
WHERE p.del_flg = 0
ORDER BY p.created_at DESC
LIMIT 20
SQL

      results = db.query(query)
      posts = make_posts(results)
=end

      posts = redis.hmget('index_cache', redis.lrange('index_posts', 0, 19))
      erb :index, layout: :layout, locals: { posts: posts, me: me }

    end

    get '/@:account_name' do
      user = db.prepare('SELECT * FROM `users` WHERE `account_name` = ? AND `del_flg` = 0').execute(
        params[:account_name]
      ).first

      if user.nil?
        return 404
      end

      results = db.prepare(<<SQL
SELECT p.id AS id, p.user_id AS user_id, p.body AS body, p.created_at AS created_at, p.ext AS ext, p.account_name AS account_name, p.del_flg AS del_flg
FROM posts p
WHERE p.user_id = ? AND p.del_flg = 0
ORDER BY p.created_at DESC
SQL
      ).execute(
        user[:id]
      )

      # results = db.prepare('SELECT `id`, `user_id`, `body`, `created_at`, `ext` FROM `posts` WHERE `user_id` = ? ORDER BY `created_at` DESC').execute(
      #   user[:id]
      # )
      posts = make_posts(results)

      comment_count = db.prepare('SELECT COUNT(*) AS count FROM `comments` WHERE `user_id` = ?').execute(
        user[:id]
      ).first[:count]

      post_ids = db.prepare('SELECT `id` FROM `posts` WHERE `user_id` = ?').execute(
        user[:id]
      ).map{|post| post[:id]}
      post_count = post_ids.length

      commented_count = 0
      if post_count > 0
        placeholder = (['?'] * post_ids.length).join(",")
        commented_count = db.prepare("SELECT COUNT(*) AS count FROM `comments` WHERE `post_id` IN (#{placeholder})").execute(
          *post_ids
        ).first[:count]
      end

      me = get_session_user()

      erb :user, layout: :layout, locals: { posts: posts, user: user, post_count: post_count, comment_count: comment_count, commented_count: commented_count, me: me }
    end

    get '/posts' do
=begin
      max_created_at = params['max_created_at']
      results = db.prepare(<<SQL
SELECT p.id AS id, p.user_id AS user_id, p.body AS body, p.created_at AS created_at, p.ext AS ext, p.account_name AS account_name, u.del_flg AS del_flg
FROM posts p JOIN users u ON p.user_id = u.id
WHERE p.created_at <= ?
ORDER BY p.created_at DESC
SQL
      ).execute(
        max_created_at.nil? ? nil : Time.iso8601(max_created_at).localtime
      )
      # results = db.prepare('SELECT `id`, `user_id`, `body`, `created_at`, `ext` FROM `posts` WHERE `created_at` <= ? ORDER BY `created_at` DESC').execute(
      #   max_created_at.nil? ? nil : Time.iso8601(max_created_at).localtime
      # )
      posts = make_posts(results)
=end

      max_created_at = params['max_created_at'].nil? ? "" : "p.created_at <= '#{params['max_created_at']}' AND "

      query = <<SQL
SELECT p.id AS id, p.user_id AS user_id, p.body AS body, p.created_at AS created_at, p.ext AS ext, p.account_name AS account_name, p.del_flg AS del_flg
FROM posts p
WHERE #{max_created_at} p.del_flg = 0
ORDER BY p.created_at DESC
LIMIT 20
SQL

      results = db.query(query)
      posts = make_posts(results)

      erb :posts, layout: false, locals: { posts: posts }
    end

    get '/posts/:id' do
      results = db.prepare(<<SQL
SELECT p.id AS id, p.user_id AS user_id, p.body AS body, p.created_at AS created_at, p.ext AS ext, p.account_name AS account_name, p.del_flg AS del_flg
FROM posts p
WHERE p.id = ?
LIMIT 20
SQL
      ).execute(
        params[:id]
      )

      # results = db.prepare('SELECT * FROM `posts` WHERE `id` = ?').execute(
      #   params[:id]
      # )
      posts = make_posts(results, all_comments: true)

      return 404 if posts.length == 0

      post = posts[0]

      me = get_session_user()

      erb :post, layout: :layout, locals: { post: post, me: me }
    end

    post '/' do
      me = get_session_user()

      if me.nil?
        redirect '/login', 302
      end

      if params['csrf_token'] != session[:csrf_token]
        return 422
      end

      if params['file']
        mime = ''
        # 投稿のContent-Typeからファイルのタイプを決定する
        if params["file"][:type].include? "jpeg"
          mime = "image/jpeg"
          ext = 'jpg'
          ext_num = 1
        elsif params["file"][:type].include? "png"
          mime = "image/png"
          ext = 'png'
          ext_num = 2
        elsif params["file"][:type].include? "gif"
          mime = "image/gif"
          ext = 'gif'
          ext_num = 3
        else
          flash[:notice] = '投稿できる画像形式はjpgとpngとgifだけです'
          redirect '/', 302
        end

        img_body = params['file'][:tempfile].read

        if img_body.length > UPLOAD_LIMIT
          flash[:notice] = 'ファイルサイズが大きすぎます'
          redirect '/', 302
        end

        file_tmppath = "/home/isucon/private_isu/webapp/public/image/tmp/#{session[:csrf_token]}.#{ext}"
        File.binwrite(file_tmppath, img_body)

        query = 'INSERT INTO `posts` (`user_id`, `body`, `account_name`, `ext`) VALUES (?,?,?,?)'
        db.prepare(query).execute(
          me[:id],
          params["body"],
          me[:account_name],
          ext_num,
        )
        created_at = Time.now
        pid = db.last_id

        file_path = "/home/isucon/private_isu/webapp/public/image/#{pid}.#{ext}"
        FileUtils.mv(file_tmppath, file_path)

        post_detail = {
          id: pid,
          account_name: me[:account_name],
          body: params["body"],
          ext: ext_num,
          created_at: created_at,
          comment_count: 0,
          comments: [],
        }

        redis.hset('index_cache', pid, render_index_post(post_detail), true)

        redirect "/posts/#{pid}", 302
      else
        flash[:notice] = '画像が必須です'
        redirect '/', 302
      end
    end

=begin
    get '/image/:id.:ext' do
      if params[:id].to_i == 0
        return ""
      end

      post = db.prepare('SELECT * FROM `posts` WHERE `id` = ?').execute(params[:id].to_i).first

      if (params[:ext] == "jpg" && post[:mime] == "image/jpeg") ||
          (params[:ext] == "png" && post[:mime] == "image/png") ||
          (params[:ext] == "gif" && post[:mime] == "image/gif")
        headers['Content-Type'] = post[:mime]
        return post[:imgdata]
      end

      return 404
    end
=end

    post '/comment' do
      me = get_session_user()

      if me.nil?
        redirect '/login', 302
      end

      if params["csrf_token"] != session[:csrf_token]
        return 422
      end

      unless /\A[0-9]+\z/.match(params['post_id'])
        return 'post_idは整数のみです'
      end
      post_id = params['post_id']

      query = 'INSERT INTO `comments` (`post_id`, `user_id`, `comment`, `account_name`) VALUES (?,?,?,?)'
      db.prepare(query).execute(
        post_id,
        me[:id],
        params['comment'],
        me[:account_name],
      )

      post_detail = {
        id: post_id,
      }

      redis.hset('index_cache', params['post_id'], render_index_post(post_detail))

      redirect "/posts/#{post_id}", 302
    end

    get '/admin/banned' do
      me = get_session_user()

      if me.nil?
        redirect '/login', 302
      end

      if me[:authority] == 0
        return 403
      end

      users = db.query('SELECT * FROM `users` WHERE `authority` = 0 AND `del_flg` = 0 ORDER BY `created_at` DESC')

      erb :banned, layout: :layout, locals: { users: users, me: me }
    end

    post '/admin/banned' do
      me = get_session_user()

      if me.nil?
        redirect '/', 302
      end

      if me[:authority] == 0
        return 403
      end

      if params['csrf_token'] != session[:csrf_token]
        return 422
      end

      query = 'UPDATE `users` SET `del_flg` = ? WHERE `id` = ?'
      query2 = 'UPDATE `posts` SET `del_flg` = ? WHERE `user_id` = ?'

      params['uid'].each do |id|
        db.prepare(query).execute(1, id.to_i)
        db.prepare(query2).execute(1, id.to_i)
      end

      redirect '/admin/banned', 302
    end

    get '/login_as/:id' do
      session[:user] = {
        id: db.prepare('SELECT * FROM users WHERE account_name = ? AND del_flg = 0').execute(params[:id]).first[:id]
      }
      session[:csrf_token] = SecureRandom.hex(16)
      redirect '/', 302
    end

    get '/tuyoi' do
      db.prepare('UPDATE `users` SET `authority` = ? WHERE `id` = ?').execute(1, session[:user][:id])
      redirect '/', 302
    end

    get '/yowai' do
      db.prepare('UPDATE `users` SET `authority` = ? WHERE `id` = ?').execute(0, session[:user][:id])
      redirect '/', 302
    end
  end
end
