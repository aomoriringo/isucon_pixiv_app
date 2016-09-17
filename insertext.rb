
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

exts = {
  'jpg' => 1,
  'png' => 2,
  'gif' => 3
}


# ps = db.query('SELECT FROM id,mime,imgdata FROM POST;')
# ps = db.query('SELECT id, mime, imgdata FROM posts;')
# count = ps.size
# ps.each_with_index do |post, i|
#   ext = mimes[post[:mime]]
#   path = "%s%s.%s" % [img_basedir, post[:id], ext]
#   per = ((i + 1) * 1.0 / count * 100).ceil
#   File.write(path, post[:imgdata])
#   puts "(%5d/%5d) %3d%% done! [%s]" % [ i + 1, count, per, path ]
# end

img_basedir = '/home/isucon/private_isu/webapp/public/image/'
count = 10000

begin
  db.query("BEGIN")
  Dir.glob("#{img_basedir}*.*").map{ |it|
    it.match(%r`\/(\d+)\.(\w+)`)
  }.select{ |m|
    m[1].to_i <= 10000
  }.sort_by{ |m|
    m[1].to_i
  }.each.with_index do |m,i|
    id = m[1].to_i
    ext = exts[m[2]]
    path = m[0]
    pps = 'UPDATE posts SET ext=%s WHERE id=%s' % [ ext, id ]
    ps = db.query(pps)
    per = (i * 1.0 / count * 100).ceil
    puts "(%5d/%5d) %3d%% done! [%s]" % [ i, count, per, path ]
  end
  db.query("COMMIT")
rescue
  db.query("ROLLBACK")
end

