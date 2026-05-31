import crypt from "node:crypto"
import fs from "node:fs";
import path from "node:path"

const byteLength = 7;
const templatePath = "template/article.md";

const slug = crypt.randomBytes(byteLength).toString('hex');

const newArticlePath = path.join('./articles/', `${slug}.md`)

try {
    fs.cpSync(templatePath, newArticlePath);
} catch (e) {
    console.log('テンプレートのコピーに失敗しました。');
    console.error(e.code)
}