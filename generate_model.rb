require 'erb'
require 'mysql2'


HOST = '127.0.0.1'
USERNAME = 'root'
PASSWORD = '123456'
DB = 'test'
DB_SEL = "DB"
PACKAGE_NAME = "test"
MODEL_DIR = 'D:/dat/'+PACKAGE_NAME+'/'
TEMPLATE = ERB.new(File.read('./model.erb'),0,'-')


GO_TYPE_DICT = {
    'smallint' => 'int8',
    'tinyint'=> 'int8',
    'varchar' => 'string',
    'int' => 'int',
    'decimal' => 'float64',
    'timestamp' => '*time.Time',
    'datetime' => '*time.Time',
    'bigint' => 'int64',
    'char' => 'string',
    'float' => 'float64',
    'text' => 'string',
    'longtext' => 'string',
    'date' => 'string',
    'time' => 'string',
    'double' => 'float64',
    'mediumblob' => 'string',
}


def get_go_type(db_name, db_type, data_type)
    if db_type == "int" and db_name.end_with?('time')
        return 'int64'
    end
    t  = GO_TYPE_DICT[db_type]
    if t == 'int64' and data_type.include?('unsigned')
        return 'uint64'
    end
    return t
end

def to_camel_case(snake_str)
    return snake_str.gsub(/^.|_./){ |match| match.size>1?match[1].upcase() : match.upcase() }
end

client = Mysql2::Client.new(
    :host     => HOST, 
    :username => USERNAME,      
    :password => PASSWORD   
    )

client.query("USE information_schema")

sql = "SELECT TABLE_TYPE,TABLE_NAME,TABLE_COMMENT FROM TABLES WHERE TABLE_SCHEMA = '#{DB}'"
    
results = client.query(sql)

if !Dir.exist?(MODEL_DIR)
    Dir.mkdir(MODEL_DIR)
else
    Dir.foreach(MODEL_DIR) do |entry|
        if entry != '.' and entry != '..' 
            file = MODEL_DIR + entry
            if !File.directory?(file)
                File.delete(file)
            end
        end
    end
end


results.each do |row|
    table_name = row['TABLE_NAME']
    is_view = row['TABLE_TYPE'] == 'VIEW'
    table_comment = row['TABLE_COMMENT']
    
    sql = "SELECT COLUMN_NAME,DATA_TYPE,COLUMN_COMMENT,COLUMN_DEFAULT,COLUMN_KEY,COLUMN_TYPE,EXTRA FROM COLUMNS WHERE TABLE_NAME = '#{table_name}' and TABLE_SCHEMA = '#{DB}'"

    columns = client.query(sql)

    struct_name = to_camel_case(table_name)
    op_struct_name = struct_name[0].downcase() + struct_name[1..-1] + 'Op'
    op_name = op_struct_name[0].upcase() + op_struct_name[1..-1]
    has_player_id = false
    primary_key = []
    primary_field = []
    primary_field_type = []
    column_list = []
    primary_key_param_list = []
    primary_keys = []
    has_time_type = false
   
    columns.each do |c|
        column_name = c['COLUMN_NAME']
        field_name = to_camel_case(column_name)
        column_type = c['DATA_TYPE']
        if column_type == 'timestamp' or column_type == 'datetime'
            has_time_type = true
        end
        data_type = c['COLUMN_TYPE']
        go_type = get_go_type(column_name, column_type, data_type)
        column_key = c['COLUMN_KEY']
        column_comment = c['COLUMN_COMMENT']
        auto_incr = (c['EXTRA'] == 'auto_increment')
        if column_name == 'player_id'
            has_player_id = true
        end
        if column_key == 'PRI'
            primary_key.push(column_name)
            primary_field.push(field_name)
            primary_field_type.push(go_type)
            primary_key_param_list.push([column_name, go_type])
            primary_keys.push(column_name +' ' + go_type)	
        end	
        column_list.push({
            'field_name' => field_name,
            'type' => go_type,
            'name' => column_name,
            'comment' => column_comment.strip(),
            'auto_incr' => auto_incr,
            'is_pk' => column_key == 'PRI',
        })
    end

    import_list= []
    import_list.push('db "plugin.arena/dat"')
    import_list.push('log "mycommon/logs"')
    import_list.push('"github.com/jmoiron/sqlx"')
    import_list.push('"fmt"')

    if has_time_type 
        import_list.push('"time"')
    end
    temp_arr1 = []
    temp_arr2 = []
    primary_key_param_list.each { |item|
        temp_arr1.push("#{item[0]} #{item[1]}")
        temp_arr2.push(item[0])
    }
    primary_key_params = temp_arr1.join(',')
    primary_key_param_names = temp_arr2.join(',')
    get_by_pk_sql = "select * from #{table_name} where #{primary_key.map {|item|item+" = ?"}.join(' and ')}"

    no_auto_increment_arr = []
    columns.each do |c|
        if c['EXTRA'] != 'auto_increment'
            no_auto_increment_arr.push(c['COLUMN_NAME'])
        end
    end

    insert_sql = "insert into #{table_name} (#{no_auto_increment_arr.join(',')}) values (#{no_auto_increment_arr.map{|item|item='?'}.join(',')})"

    insert_update_sql = "insert into #{table_name} (#{no_auto_increment_arr.join(',')}) values (#{no_auto_increment_arr.map{|item|item='?'}.join(',')}) ON DUPLICATE KEY UPDATE "

    no_pri_arr = []
    columns.each do |c|
        if c['COLUMN_KEY'] != 'PRI'
            no_pri_arr.push(c['COLUMN_NAME'])
        end
    end

    update_sql = "update #{table_name} set #{no_pri_arr.map{|item|item+"=?"}.join(',')} where #{primary_key.map{|item|item+"=?"}.join(',')}"
    
    if primary_key_params != ''
        model = TEMPLATE.result(binding)
        target_file = MODEL_DIR + table_name + '.go'
        File.open(target_file,'w') do |file|  
                file.puts model  
                puts "write #{target_file} success" 
        end  
    end 

end

Dir.chdir(MODEL_DIR) do 
    `go fmt`
    `go install ./`
end




