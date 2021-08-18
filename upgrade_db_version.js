const mysql = require('mysql2/promise');
const readline = require('readline');
const fs = require('fs');

let HOST = "127.0.0.1";
let USER = "root";
let PASSWORD = "123456";
let DB_CHANGE_PATH = "./db_changes";
let DB = "";

async function upgrade(conn, db_name, path) {
    await conn.query("USE information_schema");

    let result = await conn.query("SELECT `TABLE_NAME` FROM `TABLES` WHERE `TABLE_NAME` = 'db_version' AND `TABLE_SCHEMA` = ?", [db_name]);

    await conn.query("USE " + db_name);

    if (result[0].length == 0) {
        await conn.query(
            "CREATE TABLE `db_version` ( `version` INT,`is_execute` INT,PRIMARY KEY (`version`))  ENGINE 'InnoDb' CHARACTER SET 'utf8' COLLATE 'utf8_general_ci'"
        );
    }

    let changes_array = new Array();
    let changes_map = new Map();
    const files = fs.readdirSync(path)
    for (let f of files) {
        let version = f.split(".")[0];
        if (version) {
            changes_array.push(version);
            changes_map[version] = f;
        }
    }
    changes_array.sort();

    let db_version = new Map();
    result = await conn.query("SELECT * FROM `db_version`");
    for (let row of result[0]) {
        db_version[row.version] = row.is_execute
    }

    for (let version of changes_array) {
        if (db_version[version]) {
            continue
        }
        let file_name = changes_map[version];
        console.log("[" + db_name + "]=>" + file_name);
        let script = fs.readFileSync(path + "/" + file_name, "utf-8");
        if (script.charCodeAt(0) === 0xFEFF) {
            script = script.slice(1);
        }
        await conn.query(script);
        await conn.query("INSERT INTO `db_version` VALUES (?,?)", [version, 1]);
    }

    result = await conn.query("SELECT MAX(`version`) FROM `db_version`");
    let latest_version = result[0][0]['MAX(`version`)']
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

function ParseFlag(argv) {
    for (let arg of argv) {
        let flag = arg.split('=')
        switch (flag[0]) {
            case "DB":
                DB = flag[1]
                break
            case "HOST":
                HOST = flag[1]
                break
            case "USER":
                USER = flag[1]
                break
            case "PASSWORD":
                PASSWORD = flag[1]
                break
            case "DB_CHANGE_PATH":
                DB_CHANGE_PATH = flag[1]
                break
        }
    }
}

(async function main() {
    ParseFlag(process.argv)
    if (!DB) {
        DB = process.env.MY_DB
    }
    if (!DB) {
        DB = await Ask("请输入你的数据库名:")
    }
    let dbs = DB.split(',')
    const conn = await mysql.createConnection({ host: HOST, user: USER, password: PASSWORD, multipleStatements: true });
    try {
        await conn.beginTransaction();
        for (let db of dbs) {
            await upgrade(conn, db, DB_CHANGE_PATH);
        }
        await conn.commit();
    } catch (err) {
        await conn.rollback();
        throw err;
    } finally {
        await conn.end();
    }
})();
