const mysql = require('mysql2/promise');
const readline = require('readline');
const fs = require('fs');

const HOST = "192.168.16.217";
const USER = "root";
const PASSWORD = "123456";
const DB_CHANGE_PATH = "./db_changes";

async function upgrade(conn, db_name, path) {
    await conn.query("USE information_schema");

    let result = await conn.query("SELECT `TABLE_NAME` FROM `TABLES` WHERE `TABLE_NAME` = 'db_version' AND `TABLE_SCHEMA` = ?", [db_name]);
    let rows = result[0]

    await conn.query("USE " + db_name);

    if (rows.length == 0) {
        await conn.query(
            "CREATE TABLE `db_version` ( `version` INT,`is_execute` INT,PRIMARY KEY (`version`))  ENGINE 'InnoDb' CHARACTER SET 'utf8' COLLATE 'utf8_general_ci'"
        );
    }

    result = await conn.query("SELECT MAX(`version`) FROM `db_version`");
    let latest_version = result[0][0]['MAX(`version`)']
    if (!latest_version) {
        latest_version = 0
    }

    let changes_array = new Array();
    let changes_map = new Map();
    const files = fs.readdirSync(path)
    for (let f of files) {
        let version = f.split(".")[0];
        changes_array.push(version);
        changes_map[version] = f;
    }
    changes_array.sort();

    for (let version of changes_array) {
        let is_execute = 0
        if (version > latest_version) {
            let file_name = changes_map[version];
            console.log("[" + db_name + "]=>" + file_name);
            const script = fs.readFileSync(path + "/" + file_name, "utf-8");
            await conn.query(script);
            is_execute = 1
        }
        await conn.query("INSERT IGNORE INTO `db_version` VALUES (?,?)", [version, is_execute]);
    }

    result = await conn.query("SELECT MAX(`version`) FROM `db_version`");
    latest_version = result[0][0]['MAX(`version`)']
    console.log("数据库[" + db_name + "]已更新至版本:" + latest_version);
}


function Ask(query) {
    const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout
    })
    return new Promise(resolve => rl.question(query, ans => {
        rl.close();
        resolve(ans);
    }))
}

(async function main() {
    var DB = process.env.MY_DB
    if (!DB) {
        DB = await Ask("请输入你的数据库名:")
    }
    const conn = await mysql.createConnection({ host: HOST, user: USER, password: PASSWORD, multipleStatements: true });
    try {
        await conn.beginTransaction();
        await upgrade(conn, DB, DB_CHANGE_PATH);
        await conn.commit();
    } catch (err) {
        await conn.rollback();
        throw err;
    } finally {
        await conn.end();
    }
})();
