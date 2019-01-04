require 'mysql2'
 
HOST = '127.0.0.1'
USERNAME = 'root'
PASSWORD = '123456'
DB = "test"
PATH = "D:/changes/"

client = Mysql2::Client.new(
    :host     => HOST, 
    :username => USERNAME,      
    :password => PASSWORD   
    )

client.query("use information_schema")

sql = "SELECT `TABLE_NAME` FROM `TABLES` WHERE `TABLE_NAME` = 'db_version' AND `TABLE_SCHEMA` = '#{DB}'"
results = client.query(sql)

client.query("use #{DB}")

if results.size() == 0 
    sql = "CREATE TABLE `db_version` ( `version` INT ) ENGINE 'InnoDb' CHARACTER SET 'utf8' COLLATE 'utf8_general_ci'"
    client.query(sql)
end

sql = "SELECT `version` FROM `db_version`"
results = client.query(sql)

if results.size() == 0 
    sql = "INSERT INTO `db_version` VALUES (0);"
    client.query(sql)
    latest_version = 0
else
    results.each do |row|
        latest_version = row['version']
    end
end

changes_array = Array.new()
changes_hash = Hash.new()

Dir.foreach(PATH) do |entry|
    if entry != '.' and entry != '..'
        version = entry.delete('.sql')
        version = version.gsub('-','')
        version = version.to_i()
        if version > latest_version
            changes_array.push(version) 
            changes_hash[version] = entry
        end
    end
end

if changes_array.size() > 0 
    changes_array.sort!()
    begin
        client.query("BEGIN") 
            changes_array.each do |version|
                filename = changes_hash[version]
                puts filename
                file = File.open(PATH + filename)
                sql = file.read()
                puts sql
                results = client.query(sql)
                latest_version = version
            end
        sql = "UPDATE `db_version` SET `version` = #{latest_version}" 
        client.query(sql)
        client.query("COMMIT")
    rescue => e
        client.query("ROLLBACK")
        puts e.inspect()
    end
end

puts "数据库已经是最新版本！"

 


