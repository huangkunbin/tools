#!/usr/bin/env python
#-* coding:UTF-8 -*

import os
import json
import re
import pymysql
from jinja2 import Template
from pymysql.cursors import DictCursor

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(HERE)
CONFIG_FILE = os.path.join(ROOT_DIR, "../conf/config.json")
BASE_MODEL_DIR = os.path.join(ROOT_DIR, 'dat', 'test')
MODEL_TEMPLATE_FILE = os.path.join(HERE, "model.j2")


def loadJson(JsonPath):
    try:
        srcJson = open(JsonPath, 'r')
    except:
        print('cannot open ' + JsonPath)
        quit()

    dstJson = {}
    try:
        dstJson = json.load(srcJson)
        return dstJson
    except:
        print(JsonPath + ' is not a valid json file')
        quit()


def to_camel_case(snake_str):
    components = snake_str.split('_')
    first_char = components[0][0]
    if first_char in ('0', '1', '2', '3', '4', '5', '6', '7', '8', '9'):
        first_char = 'A' + first_char
    name = first_char.upper() + components[0][1:] + \
        "".join(x.title() for x in components[1:])
    return name

def get_go_type(db_name, db_type, data_type):
    ret = re.search("unsigned",data_type)
    if (db_type == "int" and db_name.endswith('time')) or db_name == "v":
        return 'int64'
    t  = go_type_dict.get(db_type)
    if t == 'int64' and ret != None:
        return 'uint64'
    return t

go_type_dict = {
    'smallint': 'int8',
    'tinyint': 'int8',
    'varchar': 'string',
    'int': 'int',
    'decimal': 'float64',
    'timestamp': '*time.Time',
    'datetime': '*time.Time',
    'bigint': 'int64',
    'char': 'string',
    'float': 'float64',
    'text': 'string',
    'longtext': 'string',
    'date': 'string',
    'time': 'string',
    'double': 'float64',
    'mediumblob' : 'string',
}

def rename_go1Togo(path):
    all_files = os.listdir(path)
    for filename in all_files:
        fullname = os.path.join(path, filename)
        if os.path.isfile(fullname) and filename.split('.')[-1] == "go1":
            newfilename = fullname.rsplit('.', 1)[0]
            print(fullname, newfilename)
            os.rename(fullname, newfilename + ".go")

def render(conn, db_name, db_map, model_dir, package_name, is_base_db):
    cur = conn.cursor()
    sql = """ SELECT TABLE_TYPE, TABLE_NAME,TABLE_COMMENT FROM TABLES
    WHERE table_schema = %s
    """

    cur.execute(sql, [db_name])
    result = cur.fetchall()

    if result:
        if not os.path.exists(model_dir):
            os.mkdir(model_dir)
        os.system("rm %s/*" % model_dir)
   

    with open(MODEL_TEMPLATE_FILE, mode="r",encoding="utf8") as f:
        tpl = f.read()
   

    for row in result:
        table_name = row['TABLE_NAME']
        is_view = row['TABLE_TYPE'] == 'VIEW'
        table_comment = row['TABLE_COMMENT']
        if "[logic server no use]" in table_comment:
            continue

        sql = """
        SELECT
        COLUMN_NAME,DATA_TYPE, COLUMN_COMMENT,
        COLUMN_DEFAULT,COLUMN_KEY,COLUMN_TYPE,EXTRA
        FROM COLUMNS
        WHERE TABLE_NAME = %s  and TABLE_SCHEMA = %s
        """

        cur.execute(sql, [table_name, db_name])

        columns = cur.fetchall()

        struct_name = to_camel_case(table_name)
        op_struct_name = struct_name[0].lower() + struct_name[1:] + 'Op'
        cache_struct_name = struct_name[0].lower() + struct_name[1:] + 'Cache'
        op_name = op_struct_name[0].upper() + op_struct_name[1:]
        cache_name = cache_struct_name[0].upper() + cache_struct_name[1:]
        has_player_id = False
        primary_key = []
        primary_field = []
        primary_field_type = []
        column_list = []
        primary_key_param_list = []
        primary_keys = []
        import_list= []
        import_list.append('db "plugin.arena/dat"')
        import_list.append('log "mycommon/logs"')
        import_list.append('"github.com/jmoiron/sqlx"')
        import_list.append('"fmt"')
        has_time_type = False
        
        for c in columns:
            column_name = c['COLUMN_NAME']
            field_name = to_camel_case(column_name)
            column_type = c['DATA_TYPE']
            if column_type == 'timestamp' or column_type == 'datetime':
                has_time_type = True
            data_type = c['COLUMN_TYPE']
            go_type = get_go_type(column_name, column_type, data_type)
            column_key = c['COLUMN_KEY']
            column_comment = c['COLUMN_COMMENT']
            auto_incr = (c['EXTRA'] == 'auto_increment')
            if column_name == 'player_id':
                has_player_id = True
            if column_key == 'PRI':
                primary_key.append(column_name)
                primary_field.append(field_name)
                primary_field_type.append(go_type)
                primary_key_param_list.append((column_name, go_type))
                primary_keys.append(column_name +' ' + go_type)		
            column_list.append({
                'field_name': field_name,
                'type': go_type,
                'name': column_name,
                'comment': column_comment.strip(),
                'auto_incr' : auto_incr,
                'is_pk' : column_key == 'PRI',
            })


        if has_time_type :
            import_list.append('"time"')

        primary_key_params = ','.join(
            ['%s %s' % (k[0], k[1]) for k in primary_key_param_list])
        primary_key_param_names = ','.join([k[0] for k in primary_key_param_list])

        get_by_pk_sql = 'select * from %s where %s ' % (
            table_name, ' and '.join(['%s =:%s' % (k, k) for k in primary_key]))
        get_by_pk_sql2 = 'select * from %s where %s ' % (
            table_name, ' and '.join(['%s=?' % k for k in primary_key]))
        get_by_pk_result = struct_name if len(
            primary_key) == 1 else '[]%s' % struct_name

        insert_sql = 'insert into %s(%s) values(%s)' % \
            (table_name, \
            ','.join([c['COLUMN_NAME']  for c in columns if c['EXTRA'] != 'auto_increment' ]),
            ','.join(['?' for c in columns if c['EXTRA'] != 'auto_increment']))

        insert_update_sql = 'insert into %s(%s) values(%s) ON DUPLICATE KEY UPDATE ' % \
            (table_name, \
            ','.join([c['COLUMN_NAME']  for c in columns if c['EXTRA'] != 'auto_increment' ]),
            ','.join(['?' for c in columns if c['EXTRA'] != 'auto_increment']))			

        update_sql = 'update %s set %s where %s' % \
                (table_name, \
                ','.join([c['COLUMN_NAME']+'=?'  for c in columns if c['COLUMN_KEY'] != 'PRI' ]), \
                ' and '.join(['%s=?' % k for k in primary_key]))

        db_sel = "DB"
        
        render_dict = {
            'is_view' : is_view,
            'insert_sql' : insert_sql,
            'update_sql' : update_sql,
			'insert_update_sql':insert_update_sql,
            'table_name': table_name,
            'struct_name': struct_name,
            'op_struct_name': op_struct_name,
            'op_name': op_name,
            'cache_struct_name' : cache_struct_name,
            'cache_name': cache_name,
            'db_map': db_map,
            'package_name': package_name,
            'table_comment': table_comment.strip(),
            'has_player_id': has_player_id,
            'primary_key': primary_key,
            'primary_field': primary_field,
            'primary_field_type': primary_field_type,
            'primary_key_length': len(primary_key),
            'primary_key_params': primary_key_params,
            'primary_key_param_names': primary_key_param_names,
            'primary_key_param_list': primary_key_param_list,
			'primary_keys': primary_keys,
            'get_by_pk_sql': get_by_pk_sql,
            'get_by_pk_sql2': get_by_pk_sql2,
            'get_by_pk_result': get_by_pk_result,
            'column_list': column_list,
            'is_base_db': is_base_db,
			"db_sel" : db_sel,
            "import_list" : import_list,
        }

        template = Template(tpl)
        model_file_path = os.path.join(model_dir, '%s.go' % table_name)
        if render_dict['primary_key_params']!="":
            with open(model_file_path, mode="w",encoding="utf8") as f:
                f.write(template.render(**render_dict))
            

        print('write %s success' % model_file_path)

       
   
   
    old_dir = os.getcwd()
    os.chdir(model_dir)
   
    os.system("go fmt")
    os.system("go install ./")
    
    os.chdir(old_dir)

   
    cur.close()
    conn.close()
    
    
    
    
    
    
def run():
    # print(CONFIG_FILE)
    config = loadJson(CONFIG_FILE)
    # print("config:", config)
    # print(config['mysql']['db'])
    mysqlConfig = config['mysql']

    db_conn = pymysql.connect(host=mysqlConfig['ip'],
                                   port=mysqlConfig['port'],
                                   charset='utf8',
                                   user=mysqlConfig['user'],
                                   passwd=mysqlConfig['passwd'],
                                   db='information_schema', 
                                   cursorclass=DictCursor)
    
    render(db_conn, config['mysql']['db'],
           'test', BASE_MODEL_DIR, 'test', False)



if __name__ == "__main__":
        run()
        
        
    