require 'mysql2'
 
HOST = '127.0.0.1'
USERNAME = 'root'
PASSWORD = '123456'
DB_CHANGE_PATH = './db_changes/'

client = Mysql2::Client.new(
    :host     => HOST, 
    :username => USERNAME,      
    :password => PASSWORD,
    :flags =>  Mysql2::Client::MULTI_STATEMENTS,
    )


class C
    def initialize(c)
       @client = c
    end

    def query(sql)
        @client.query(sql)
        while @client.next_result
            result = @client.store_result
        end
    end
    
    def update (db,path)
        @client.query("USE information_schema")
    
        sql = "SELECT `TABLE_NAME` FROM `TABLES` WHERE `TABLE_NAME` = 'db_version' AND `TABLE_SCHEMA` = '#{db}'"
        results = @client.query(sql)
    
        @client.query("USE #{db}")
    
        if results.size == 0 
            sql = "CREATE TABLE `db_version` ( `version` INT ) ENGINE 'InnoDb' CHARACTER SET 'utf8' COLLATE 'utf8_general_ci'"
            @client.query(sql)
        end
    
        sql = "SELECT `version` FROM `db_version`"
        results = @client.query(sql)
    
        if results.size == 0 
            sql = "INSERT INTO `db_version` VALUES (0)"
            @client.query(sql)
            latest_version = 0
        else
            results.each do |row|
                latest_version = row['version']
            end
        end
    
        changes_array = Array.new()
        changes_hash = Hash.new()
    
        Dir.foreach(path) do |entry|
            if entry != '.' and entry != '..'
                extname = File.extname(entry)
                version = entry.delete(extname)
                version = version.gsub('-','')
                version = version.to_i()
                if version > latest_version
                    changes_array.push(version) 
                    changes_hash[version] = entry
                end
            end
        end
    
        if changes_array.size == 0 
            return
        end
        
        changes_array.sort!()
        begin
            @client.query("BEGIN") 
                changes_array.each do |version|
                    filename = changes_hash[version]
                    puts "[#{db}]=>"+filename
                    script = File.read(path + "/" + filename)
                    # puts script
                    sql = ""
                    if File.extname(filename) == ".rb"
                        eval(script)
                    else
                        self.query(script)
                    end
                    latest_version = version
                end
            sql = "UPDATE `db_version` SET `version` = #{latest_version}" 
            @client.query(sql)
            @client.query("COMMIT")
        rescue => e
            @client.query("ROLLBACK")
            puts e.inspect()
            raise
        end
        
        puts "数据库[#{db}]已更新至版本:#{latest_version}"
    end

 end
 

c = C.new(client)

Dir.foreach(DB_CHANGE_PATH) do |entry|
    if entry != '.' and entry != '..'
       path = "#{DB_CHANGE_PATH}" + entry
       if File.directory?(path)
          c.update(entry,path)
       end
    end
end

puts "所有数据库已更新至最新版本"

