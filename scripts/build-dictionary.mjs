#!/usr/bin/env node
// =============================================================================
// 从 ECDICT（https://github.com/skywind3000/ECDICT，MIT）生成 App 内置的离线词典与雅思核心词表。
//
// 用法:
//   node scripts/build-dictionary.mjs [ecdict.csv 路径]
//
// 不传路径时下载 ECDICT 的 ecdict.csv 到 local/cache/（约 66 MB，只下载一次）。
// 输出：
//   IELTSCDPractice/Content/dictionary/ecdict.tsv        词典（词、音标、中文释义、英文释义）
//   IELTSCDPractice/Content/dictionary/ECDICT_LICENSE.txt
//   IELTSCDPractice/Content/vocabulary/ielts-core.json   ECDICT 标记为 IELTS 的词，按词频排序
// =============================================================================
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const CONTENT = path.join(ROOT, 'IELTSCDPractice', 'Content');
const CACHE = path.join(ROOT, 'local', 'cache');
const SOURCE_URL = 'https://raw.githubusercontent.com/skywind3000/ECDICT/master/ecdict.csv';
const LICENSE_URL = 'https://raw.githubusercontent.com/skywind3000/ECDICT/master/LICENSE';

async function download(url, file) {
    const response = await fetch(url);
    if (!response.ok) throw new Error(`下载失败 ${url}：${response.status}`);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, Buffer.from(await response.arrayBuffer()));
}

async function source() {
    if (process.argv[2]) return path.resolve(process.argv[2]);
    const file = path.join(CACHE, 'ecdict.csv');
    if (!fs.existsSync(file)) {
        console.log('下载 ECDICT…');
        await download(SOURCE_URL, file);
    }
    return file;
}

/** RFC 4180 CSV：字段可用双引号包裹，引号内的 "" 表示一个引号 */
function* parseCSV(text) {
    let row = [];
    let field = '';
    let quoted = false;
    for (let i = 0; i < text.length; i++) {
        const c = text[i];
        if (quoted) {
            if (c === '"') {
                if (text[i + 1] === '"') { field += '"'; i++; } else quoted = false;
            } else field += c;
        } else if (c === '"') quoted = true;
        else if (c === ',') { row.push(field); field = ''; }
        else if (c === '\n' || c === '\r') {
            if (c === '\r' && text[i + 1] === '\n') i++;
            row.push(field);
            yield row;
            row = [];
            field = '';
        } else field += c;
    }
    if (field || row.length) { row.push(field); yield row; }
}

// 词典收录：考试类标签（雅思、托福、六级、考研、四级、GRE、高考）、柯林斯星级或牛津 3000 核心词
const EXAM_TAGS = new Set(['ielts', 'toefl', 'cet6', 'ky', 'cet4', 'gre', 'gk']);
const clean = (value) => value.replace(/\t/g, ' ').replace(/\r/g, '').trim();

const csv = fs.readFileSync(await source(), 'utf8');
const rows = parseCSV(csv);
const header = rows.next().value;
const col = Object.fromEntries(header.map((name, index) => [name, index]));

const dictionary = [];
const core = [];
for (const row of rows) {
    const word = row[col.word]?.trim();
    const translation = clean(row[col.translation] ?? '');
    if (!word || !translation || !/^[a-z][a-z'-]*$/i.test(word)) continue;
    const tags = new Set((row[col.tag] ?? '').split(' ').filter(Boolean));
    const collins = Number(row[col.collins]) || 0;
    const oxford = Number(row[col.oxford]) || 0;
    if (![...tags].some((tag) => EXAM_TAGS.has(tag)) && collins === 0 && oxford === 0) continue;
    dictionary.push([word, clean(row[col.phonetic] ?? ''), translation, clean(row[col.definition] ?? '')]);

    // 核心词表：ECDICT 标为雅思词汇、且不是中考词汇（in、on、say 这类基础词不必再背）
    if (tags.has('ielts') && !tags.has('zk') && /^[a-z][a-z-]*$/.test(word)) {
        // 词频排名：COCA（frq）优先，其次 BNC；0 表示没有排名
        const rank = Number(row[col.frq]) || Number(row[col.bnc]) || 0;
        const meaning = translation.split('\\n').filter((line) => !line.startsWith('[')).slice(0, 2).join('；');
        core.push({ word, meaning, rank });
    }
}

dictionary.sort((a, b) => a[0].localeCompare(b[0]));
const maxRank = Math.max(...core.map((w) => w.rank));
const coreWords = core
    .sort((a, b) => (a.rank || Infinity) - (b.rank || Infinity))
    .map(({ word, meaning, rank }) => ({
        word,
        meaning,
        example: '',
        frequency: rank ? Number((1 - (rank - 1) / maxRank).toFixed(4)) : 0,
    }));

fs.mkdirSync(path.join(CONTENT, 'dictionary'), { recursive: true });
fs.mkdirSync(path.join(CONTENT, 'vocabulary'), { recursive: true });
fs.writeFileSync(path.join(CONTENT, 'dictionary', 'ecdict.tsv'), dictionary.map((fields) => fields.join('\t')).join('\n') + '\n');
fs.writeFileSync(path.join(CONTENT, 'vocabulary', 'ielts-core.json'), JSON.stringify(coreWords));

const license = path.join(CACHE, 'ECDICT_LICENSE');
if (!fs.existsSync(license)) await download(LICENSE_URL, license);
fs.copyFileSync(license, path.join(CONTENT, 'dictionary', 'ECDICT_LICENSE.txt'));

console.log(`词典：${dictionary.length} 条`);
console.log(`雅思核心词：${coreWords.length} 个`);
