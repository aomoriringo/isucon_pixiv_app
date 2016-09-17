
require 'mysql2'
def config
  @config ||= {
    db: {
      host: ENV['ISUCONP_DB_HOST'] || 'localhost',
      port: 3306,
      username: 'isucon',
      password: 'isucon',
      database: ENV['ISUCONP_DB_NAME'] || 'isuconp',
    },
  }
end

def db
  unless @client
    @client = Mysql2::Client.new(
      host: config[:db][:host],
      port: config[:db][:port],
      username: config[:db][:username],
      password: config[:db][:password],
      database: config[:db][:database],
      encoding: 'utf8mb4',
      reconnect: true,
    )
    @client.query_options.merge!(symbolize_keys: true, database_timezone: :local, application_timezone: :local)
  end
  @client
end
require 'pp'

mimes = {
  "image/jpeg" => 'jpg',
  "image/gif" => 'gif',
  "image/png" => 'png'
}

img_basedir = '/home/isucon/private_isu/webapp/public/image/'

# ps = db.query('SELECT FROM id,mime,imgdata FROM POST;')
ps = db.query('SELECT id, mime, imgdata FROM posts;')
count = ps.size
ps.each_with_index do |post, i|
  ext = mimes[post[:mime]]
  path = "%s%s.%s" % [img_basedir, post[:id], ext]
  per = ((i + 1) * 1.0 / count * 100).ceil
  File.write(path, post[:imgdata])
  puts "(%5d/%5d) %3d%% done! [%s]" % [ i + 1, count, per, path ]
end
