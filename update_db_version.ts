import { Client } from "https://deno.land/x/mysql/mod.ts";

const HOST = "127.0.0.1";
const USERNAME = "root";
const PASSWORD = "123456";
const DB_CHANGE_PATH = "./db_changes/";

class DB {
  client: Client;

  constructor(client: Client) {
    this.client = client;
  }

  async update(db_name: string, path: string): Promise<void> {
    await this.client.execute("USE information_schema");

    let results = await this.client.execute(
      "SELECT `TABLE_NAME` FROM `TABLES` WHERE `TABLE_NAME` = 'db_version' AND `TABLE_SCHEMA` = ?",
      [db_name]
    );

    await this.client.execute("USE ??", [db_name]);

    if (results.rows.length == 0) {
      await this.client.execute(
        "CREATE TABLE `db_version` ( `version` INT ) ENGINE 'InnoDb' CHARACTER SET 'utf8' COLLATE 'utf8_general_ci'"
      );
    }

    results = await this.client.execute("SELECT `version` FROM `db_version`");

    let latest_version: number;
    if (results.rows.length == 0) {
      await this.client.execute("INSERT INTO `db_version` VALUES (0)");
      latest_version = 0;
    } else {
      latest_version = results.rows[0]["version"];
    }

    let changes_array = new Array();
    let changes_map = new Map();

    const files = await Deno.readDir(path);

    for (let f of files) {
      if (!f.isFile) {
        continue;
      }

      let version = Number(
        f.name
          .split(".")[0]
          .split("-")
          .join("")
      );

      if (version > latest_version) {
        changes_array.push(version);
        changes_map[version] = f.name;
      }
    }

    if (changes_array.length == 0) {
      return;
    }

    changes_array.sort();

    await this.client.transaction(async conn => {
      for (let version of changes_array) {
        let file_name = changes_map[version];

        console.log("[" + db_name + "]=>" + file_name);

        const decoder = new TextDecoder("utf-8");
        const data = await Deno.readFile(path + "/" + file_name);
        let script = decoder.decode(data);

        if (script == "") {
          console.log("内容为空,忽略");
          continue;
        }

        if (file_name.split(".")[1] == "ts") {
          // TODO eval(script);
        } else {
          await conn.execute(script);
        }

        latest_version = version;
      }

      await conn.execute("UPDATE `db_version` SET `version` = ?", [
        latest_version
      ]);
    });

    console.log("数据库" + db_name + "已更新至版本:" + latest_version);
  }
}

(async function main() {
  const client = await new Client().connect({
    hostname: HOST,
    username: USERNAME,
    password: PASSWORD
  });

  const db = new DB(client);

  const files = await Deno.readDir(DB_CHANGE_PATH);

  for (let f of files) {
    if (f.isDirectory) {
      let path = DB_CHANGE_PATH + f.name;
      await db.update(f.name, path);
    }
  }

  await client.close();

  console.log("所有数据库已更新至最新版本");
})();
