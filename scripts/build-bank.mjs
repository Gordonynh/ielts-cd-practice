#!/usr/bin/env node
// =============================================================================
// 将 ielts-cd-bank/1 格式的题库源文件转换为 App 内置格式（机考引擎可直接使用）。
// 格式说明见 docs/题库数据格式.md。
//
// 用法:
//   node scripts/build-bank.mjs [题库源文件目录，默认 bank-source/]
//
// 输出: IELTSCDPractice/Content/bank/
//   index.json                         阅读篇目、整套试卷、听力试卷索引
//   reading/exams/<id>.json            阅读（每篇一个文件，id = <套题id>-p<Part>）
//   reading/explanations/<id>.json     阅读解析与段落翻译
//   listening/exams/<id>.json          听力（每个 Section 一个文件，id = <套题id>-l<Part>）
//   listening/explanations/<id>.json   听力解析
//   images/                            题目插图
// =============================================================================
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
// 默认使用项目内的 bank-source/（已排除在 git 之外）
const BANK = path.resolve(process.argv[2] || path.join(ROOT, 'bank-source'));
const machine = fs.existsSync(path.join(BANK, 'translations.json'))
    ? JSON.parse(fs.readFileSync(path.join(BANK, 'translations.json'), 'utf8'))
    : { reading: {}, listening: {} };
const OUT = path.join(ROOT, 'IELTSCDPractice', 'Content', 'bank');
const FORMATS = new Set(['ielts-cd-bank/1']);

if (!fs.existsSync(path.join(BANK, 'sets'))) {
    console.error(`ERROR: 找不到题库包 ${BANK}/sets`);
    process.exit(1);
}

const warnings = [];
const warn = (message) => warnings.push(message);

// -----------------------------------------------------------------------------
// 文本工具
// -----------------------------------------------------------------------------
const ENTITIES = {
    darr: '↓', uarr: '↑', rarr: '→', larr: '←', nbsp: ' ', amp: '&', quot: '"', apos: "'", lt: '<', gt: '>',
    ndash: '–', mdash: '—', hellip: '…', minus: '−', shy: '', bdquo: '„', sup2: '²', sup3: '³',
    aacute: 'á', eacute: 'é', iacute: 'í', oacute: 'ó', uacute: 'ú', auml: 'ä', euml: 'ë', ouml: 'ö', uuml: 'ü',
    ccedil: 'ç', scaron: 'š', ntilde: 'ñ', agrave: 'à', egrave: 'è',
};

/** 原始数据中偶尔残留 HTML 实体（如 &darr;），先还原成字符再转义。 */
function decodeEntities(value) {
    // 有些文本被转义了两次（&amp;sup2;），解码两遍
    let text = String(value ?? '');
    for (let i = 0; i < 2; i += 1) {
        text = text
            .replace(/&([a-z]+[0-9]?);/gi, (m, name) => ENTITIES[name.toLowerCase()] ?? m)
            .replace(/&#(\d+);/g, (m, code) => String.fromCharCode(Number(code)));
    }
    return text;
}

function escapeHtml(value) {
    return decodeEntities(value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

// -----------------------------------------------------------------------------
// 修复粘连：题库包里不少题目把几行内容直接拼在一起（如 "Staff are very friendlyNeed to pay"、
// "**The importance of language**The wheel"、"follows this {{37}}While some cities"）。
// -----------------------------------------------------------------------------

/** 小写字母后紧跟大写单词时，这些前缀属于人名或品牌（McGaughey、DeClerck、VanDam、iToys、EcoVero），不拆开 */
function isNamePrefix(token) {
    return /^[a-z]$/.test(token) || (/^[A-Z][a-z]{0,3}$/.test(token) && token.length <= 4);
}

/**
 * 找出粘连位置。返回 [{ index, kind }]：
 * - break：应另起一行（小写/数字/右括号紧跟大写单词，或 **标题** 后紧跟正文）
 * - stop：句末标点后紧跟下一句（段落中补空格，按行显示时换行）
 * - sentence：空位 {{n}} 后紧跟大写单词，原卷此处为句末
 * - label：表单中的 **字段名:** 前（按行显示时换行）
 * - space：只缺空格
 */
function gluePoints(value) {
    const text = String(value ?? '');
    const points = [];
    // 加粗、斜体内部不拆
    const spans = [...text.matchAll(/\*\*[^*\n]+\*\*|\*[^*\n]+\*/g)].map((m) => [m.index, m.index + m[0].length]);
    const inside = (index) => spans.some(([a, b]) => index > a && index < b);
    const add = (index, kind) => {
        if (index > 0 && index < text.length && !inside(index)) points.push({ index, kind });
    };
    const capital = '(?=[A-Z][a-z]|[AI]\\s)';

    for (const m of text.matchAll(/\*\*([^*\n]+)\*\*/g)) {
        const end = m.index + m[0].length;
        const label = /:\s*$/.test(m[1]);
        // **字段名:**值 → 补空格；**标题**正文 → 换行
        if (/^[A-Za-z0-9(‘'"£$]/.test(text.slice(end))) add(end, label ? 'space' : 'break');
        // 表单中前面已有内容的字段名另起一行
        if (label && text.slice(0, m.index).trim() && !/[·•]\s*$/.test(text.slice(0, m.index))) add(m.index, 'label');
    }
    // 小写或数字、右括号紧跟大写单词：friendlyNeed、18Currently、(CEOs)Many
    for (const m of text.matchAll(new RegExp('([A-Za-z]*)([a-z0-9)])' + capital, 'g'))) {
        const token = m[1] + m[2];
        const after = text.slice(m.index + m[0].length);
        if (/[a-z]$/.test(m[2]) && isNamePrefix(token)) continue;
        // 数字后的单个大写字母（3D、850AD）不是新句子
        if (/[0-9]/.test(m[2]) && /^[AI]\s/.test(after)) continue;
        add(m.index + m[0].length, 'break');
    }
    // 空位后紧跟大写单词或其他文字
    for (const m of text.matchAll(new RegExp('\\}\\}(?:' + capital.slice(3, -1) + ')', 'g'))) add(m.index + 2, 'sentence');
    for (const m of text.matchAll(/\}\}(?=[a-z0-9(£$€])/g)) add(m.index + 2, 'space');
    // 空位后紧跟加粗小标题：{{6}}**Possible time and place of theft**
    for (const m of text.matchAll(/\}\}(?=\*\*[^*:]+\*\*)/g)) add(m.index + 2, 'break');
    // 句末标点后缺空格：effective?According、a.m.Last、11 .The；冒号等只补空格：Name:Luisa
    for (const m of text.matchAll(new RegExp('([.?!])' + capital, 'g'))) add(m.index + 1, 'stop');
    for (const m of text.matchAll(new RegExp('(?<=\\S)([:;,])' + capital, 'g'))) add(m.index + 1, 'space');
    return points.sort((a, b) => a.index - b.index);
}

/** 段落中的文字：加空格、补句号、标题后换行 */
function deglueInline(value) {
    const text = String(value ?? '');
    let result = '';
    let cursor = 0;
    for (const point of gluePoints(text)) {
        if (point.index <= cursor || point.kind === 'label') continue;
        result += text.slice(cursor, point.index);
        result += point.kind === 'break' ? '\n' : point.kind === 'sentence' ? '. ' : ' ';
        cursor = point.index;
    }
    return result + text.slice(cursor);
}

/** 表格单元格、笔记等按行显示的内容：在粘连处与「·」要点处拆成多行 */
function splitGlued(value) {
    const pieces = [];
    for (const part of String(value ?? '').split(/\s*[·•]\s*/)) {
        let cursor = 0;
        for (const point of gluePoints(part)) {
            if (point.index <= cursor || point.kind === 'space') continue;
            pieces.push(part.slice(cursor, point.index));
            cursor = point.index;
        }
        pieces.push(part.slice(cursor));
    }
    return pieces.map((p) => p.trim()).filter(Boolean);
}

/** **加粗**、*斜体*，并去掉空的 `****`。题目文字会修复粘连，文章正文保持原样。 */
function inline(value, { deglue = true } = {}) {
    let text = escapeHtml(deglue ? deglueInline(value) : value).replace(/\*{4,}/g, ' ');
    text = text.replace(/\*\*([^*]+?)\*\*/g, '<strong>$1</strong>');
    text = text.replace(/\*([^*\n]+?)\*/g, '<em>$1</em>');
    text = text.replace(/\*/g, '');
    return text.replace(/\n/g, '<br>');
}

function gapInput(number) {
    return `<input class="blank" name="q${number}">`;
}

/** 渲染行内格式并把 {{n}} 换成答题框；没有答案的空位保留为普通横线。 */
function withBlanks(value, known, render = gapInput) {
    return inline(value).replace(/\{\{\s*(\d+)\s*\}\}/g, (match, number) => {
        if (known.has(Number(number))) return render(Number(number));
        return '<span class="plain-gap">________</span>';
    });
}

/** 表格单元格：粘在一起的几条要点分行显示（原卷为逐条列出） */
function tableCell(value, known) {
    const pieces = splitGlued(value);
    if (pieces.length <= 1) return withBlanks(value, known);
    return `<ul class="cell-list">${pieces.map((piece) => `<li>${withBlanks(piece, known)}</li>`).join('')}</ul>`;
}

function blankNumbers(value) {
    return [...String(value ?? '').matchAll(/\{\{\s*(\d+)\s*\}\}/g)].map((m) => Number(m[1]));
}

/**
 * 部分题组把笔记「逐行累加」存储：每一行都重复上一行的全部内容再追加新内容，
 * 直接渲染会让同一个空位出现多次。这里只保留每行新增的部分。
 * 返回 [{ index, text, flattened }]，flattened 表示该段来自被压平的笔记，需要再拆分。
 */
function uncumulate(texts) {
    const result = [];
    let previous = '';
    texts.forEach((raw, index) => {
        const value = String(raw ?? '').trim();
        if (previous && value.startsWith(previous)) {
            if (result.length) result[result.length - 1].flattened = true;
            const rest = value.slice(previous.length).trim();
            if (rest) result.push({ index, text: rest, flattened: true });
        } else {
            result.push({ index, text: value, flattened: false });
        }
        previous = value;
    });
    return result;
}

/**
 * 把压平的笔记拆回结构：**小标题**、「·」要点、「- 」子要点。
 * 返回 [{ text, heading, sub }]。
 */
function splitFlattened(text) {
    const parts = [];
    let cursor = 0;
    // 去掉空的加粗 `****`（常紧跟在小标题的 `**` 之后，如 `**标题******`）
    const value = String(text).replace(/\*{4}(?=[^*]|$)/g, ' ');
    for (const match of value.matchAll(/\*\*([^*]+)\*\*/g)) {
        const start = match.index;
        const end = start + match[0].length;
        const before = value.slice(cursor, start);
        const glued = start > 0 && !/\s/.test(value[start - 1]);
        const atStart = !before.trim();
        const after = value.slice(end);
        if (/\{\{/.test(match[1])) continue;
        if (/^\s*:/.test(after)) {
            // 「**Name**: …」是加粗字段名：粘在上一句后面时另起一行，但不是小标题
            if (glued && before.trim()) {
                parts.push({ text: before });
                cursor = start;
            }
            continue;
        }
        const heading = !/^\s*[,.;)]/.test(after) && (atStart || glued || /^(\S|\s*[·•]|\s*\*\*)/.test(after));
        if (!heading) continue;
        if (before.trim()) parts.push({ text: before });
        parts.push({ text: match[1].trim(), heading: true });
        cursor = end;
    }
    parts.push({ text: value.slice(cursor) });
    const lines = [];
    for (const part of parts) {
        if (part.heading) { lines.push(part); continue; }
        // 「·」「•」要点、粘在上一句后面的 (i)/(ii) 编号、空位后直接接大写开头的新句
        for (const bullet of part.text.split(/\s*[·•]\s*|(?<=\S)(?=\((?:i{1,3}|iv|vi{0,3}|ix|x)\)\s)|(?<=\}\})(?=[A-Z][a-z])/)) {
            splitDashes(bullet).forEach((piece) => lines.push(piece));
        }
    }
    return lines;
}

/** 「- 」「–」子要点（保留 high- and low- 这类省略连字符，不拆数字区间 1990–2000）。返回 [{ text, sub }]。 */
function splitDashes(text) {
    const leadingPattern = /^\s*(?:-\s+|-(?=[A-Za-z{])|–\s*)/;
    const leading = leadingPattern.test(text);
    return String(text).replace(leadingPattern, '')
        .split(/(?<=[A-Za-z)}’':])\s*-\s+(?!(?:and|or|to)\b)(?=[A-Za-z{‘'])|(?<=[\s.)}])-(?=[A-Za-z{])|(?<=\.)-\s*(?=[A-Za-z{])|(?<!\d)\s*–\s*(?=[^\d\s])/)
        .map((piece, i) => ({ text: piece.trim(), sub: leading || i > 0 }))
        .filter((piece) => piece.text);
}

function cleanOption(value) {
    return String(value ?? '').replace(/^[\s.。·]+/, '').trim();
}

function titleCase(value) {
    const text = String(value ?? '').trim();
    if (!text || /[a-z]/.test(text)) return text;
    return text.toLowerCase().replace(/(^|[\s(‘'"-])([a-z])/g, (m, p, c) => p + c.toUpperCase());
}

/** "Stepwells*A millennium ago ...*" → 标题 + 导语；去掉 "*Questions 1-7 *" 这类残留。 */
function splitHeading(raw) {
    const text = String(raw ?? '').trim();
    let heading = text;
    let sub = '';
    const match = text.match(/^([^*]*?)\s*\*([^*]+)\*\s*(.*)$/s);
    if (match) {
        heading = (match[1] + ' ' + match[3]).trim();
        sub = match[2].trim();
    }
    if (/^Questions?\s*\d/i.test(sub)) sub = '';
    heading = heading.replace(/\*/g, '').replace(/\s+/g, ' ').trim();
    return { heading, sub };
}

// 题库包里个别文章的标题其实是 A 段正文：「A Schools are seeing a dramatic increase…」，取第一句作标题
function paragraphAsTitle(title) {
    if (title.length <= 90 || !/^[A-H]\s+[A-Z]/.test(title)) return title;
    const sentence = title.replace(/^[A-H]\s+/, '').split(/(?<=[.?!])\s/)[0].replace(/[.]$/, '');
    if (sentence.length <= 90) return sentence;
    return sentence.slice(0, 90).replace(/\s+\S*$/, '') + '…';
}

function isGenericTitle(title) {
    return !title || /^(section|passage|part)\s*\d+$/i.test(title.trim());
}

// -----------------------------------------------------------------------------
// 题目说明
// -----------------------------------------------------------------------------
function stripInstructionPrefix(value) {
    // 补上句号后缺失的空格：「below.Write ONE WORD」
    let text = String(value ?? '').replace(/\s+/g, ' ').replace(/([a-z])\.(?=[A-Z])/g, '$1. ').trim();
    const prefix = /^(?:SECTION\s*\d+\s*[:.]?\s*|Questions?\s*\d+\s*(?:(?:[-–—~]|to|and)\s*\d+)?\s*[:.]?\s*)/i;
    let previous;
    do {
        previous = text;
        text = text.replace(prefix, '').trim();
    } while (text !== previous);
    return text;
}

function instructionHtml(group, context) {
    const raw = stripInstructionPrefix(group.instruction);
    let sentences = raw.split(/(?<=[.?!])\s+(?=[A-Z(“"])/).map((s) => s.trim()).filter(Boolean);
    // 机考版不出现答题卡相关的说法
    sentences = sentences.filter((s) => !/answer sheet/i.test(s) && !/^You should spend about/i.test(s));

    if (group.type === 'true_false_not_given' || group.type === 'yes_no_not_given') {
        const yes = group.type === 'yes_no_not_given';
        const lead = sentences.find((s) => /^Do the following statements/i.test(s))
            || (yes
                ? `Do the following statements agree with the claims of the writer in ${context.passageLabel}?`
                : `Do the following statements agree with the information given in ${context.passageLabel}?`);
        const rows = yes
            ? [['YES', 'if the statement agrees with the claims of the writer'],
                ['NO', 'if the statement contradicts the claims of the writer'],
                ['NOT GIVEN', 'if it is impossible to say what the writer thinks about this']]
            : [['TRUE', 'if the statement agrees with the information'],
                ['FALSE', 'if the statement contradicts the information'],
                ['NOT GIVEN', 'if there is no information on this']];
        return `<p>${inline(lead)}</p><p>Choose</p><table class="tfng-key">${rows
            .map(([key, text]) => `<tr><td><strong>${key}</strong></td><td>${text}</td></tr>`).join('')}</table>`;
    }

    const limit = group.wordLimit ? String(group.wordLimit).trim() : '';
    if (limit && !sentences.some((s) => s.toUpperCase().includes(limit.toUpperCase()))) {
        sentences.push(context.skill === 'listening'
            ? `Write ${limit} for each answer.`
            : `Choose ${limit} from the passage for each answer.`);
    }
    return sentences.map((sentence) => {
        let html = inline(sentence);
        if (limit) {
            const index = html.toUpperCase().indexOf(limit.toUpperCase());
            if (index >= 0) {
                html = html.slice(0, index) + '<strong>' + html.slice(index, index + limit.length) + '</strong>'
                    + html.slice(index + limit.length);
            }
        }
        html = html.replace(/\b(NB)\b/, '<strong>$1</strong>').replace(/\b(TWO|THREE|FOUR|FIVE)\b/g, '<strong>$1</strong>');
        return `<p>${html}</p>`;
    }).join('');
}

function rangeLabel(numbers) {
    const sorted = [...numbers].sort((a, b) => a - b);
    if (!sorted.length) return '';
    const first = sorted[0];
    const last = sorted[sorted.length - 1];
    if (first === last) return `Question ${first}`;
    if (sorted.length === 2 && last === first + 1) return `Questions ${first} and ${last}`;
    return `Questions ${first}–${last}`;
}

function letterRange(instruction, fallback, answers = []) {
    // 原文常把 A–I 误写成 A-l（小写 L）
    const match = String(instruction ?? '').match(/\b([A-Z])\s*[-–—]\s*([A-Za-z])\b/);
    let letters = fallback;
    if (match) {
        const end = match[2] === 'l' ? 'I' : match[2].toUpperCase();
        if (match[1] < end) {
            letters = [];
            for (let c = match[1].charCodeAt(0); c <= end.charCodeAt(0); c += 1) letters.push(String.fromCharCode(c));
        }
    }
    const extra = answers.map((a) => String(a).trim().toUpperCase()).filter((a) => /^[A-Z]$/.test(a) && !letters.includes(a));
    return [...letters, ...extra].sort();
}

// -----------------------------------------------------------------------------
// 题组 → 机考 HTML
// -----------------------------------------------------------------------------
const KIND = {
    true_false_not_given: 'true_false_not_given',
    yes_no_not_given: 'yes_no_not_given',
    multiple_choice: 'single_choice',
    multiple_choice_multi: 'multi_choice',
    matching_headings: 'matching_headings',
    matching_information: 'matching_information',
    matching_features: 'matching_features',
    matching_sentence_endings: 'matching_sentence_endings',
    sentence_completion: 'sentence_completion',
    summary_completion: 'summary_completion',
    summary_completion_options: 'summary_completion',
    note_completion: 'notes_completion',
    table_completion: 'table_completion',
    flow_chart_completion: 'flow_chart_completion',
    diagram_label_completion: 'diagram_completion',
    short_answer: 'short_answer',
};

function asList(answer) {
    if (Array.isArray(answer)) return answer.map((a) => String(a).trim()).filter(Boolean);
    const text = String(answer ?? '').trim();
    return text ? [text] : [];
}

function poolItems(options, attribute, reuse, className = 'drag-item') {
    return Object.entries(options).map(([key, text]) =>
        `<div class="${className}" draggable="true" data-${attribute}="${escapeHtml(key)}"${reuse ? ' data-clone="true"' : ''}><strong>${escapeHtml(key)}</strong>&nbsp;${inline(cleanOption(text))}</div>`
    ).join('');
}

/**
 * 返回 { html, numbers, answers, multiSelect, allowReuse, zones }。
 * zones：需要插入原文段落前的标题匹配答题框 [{ number, label }]。
 */
function renderGroup(group, context) {
    const answers = {};
    const numbers = [];
    let body = '';
    let multiSelect = false;
    let allowReuse = !!group.allowReuse;
    const zones = [];

    const addAnswer = (number, value) => {
        numbers.push(number);
        answers[number] = asList(value);
        if (!answers[number].length) warn(`${context.id} 第 ${number} 题没有答案`);
    };

    // 原始数据中的占位文字 "undefined"
    const isPlaceholder = (value) => String(value ?? '').trim() === 'undefined';
    if (isPlaceholder(group.title)) group = { ...group, title: '' };
    if (Array.isArray(group.lines)) group = { ...group, lines: group.lines.filter((l) => !isPlaceholder(typeof l === 'string' ? l : l.text)) };
    if (group.image && group.type !== 'diagram_label_completion') {
        const name = path.basename(group.image);
        if (fs.existsSync(path.join(BANK, 'images', name))) {
            context.images.add(name);
            body += `<figure class="diagram"><img src="content/bank/images/${encodeURIComponent(name)}" alt="Diagram"></figure>`;
        }
    }

    switch (group.type) {
        case 'true_false_not_given':
        case 'yes_no_not_given': {
            const choices = group.type === 'true_false_not_given' ? ['TRUE', 'FALSE', 'NOT GIVEN'] : ['YES', 'NO', 'NOT GIVEN'];
            for (const q of group.questions) {
                addAnswer(q.number, String(q.answer).toUpperCase());
                body += `<div class="question-item"><p><strong>${q.number}</strong> ${inline(q.text)}</p><div class="radio-options">${choices
                    .map((c) => `<label><input type="radio" name="q${q.number}" value="${c}"> ${c}</label>`).join('')}</div></div>`;
            }
            break;
        }
        case 'multiple_choice': {
            for (const q of group.questions) {
                addAnswer(q.number, q.answer);
                body += `<div class="question-item"><p><strong>${q.number}</strong> ${inline(q.text)}</p><div class="radio-options">${Object.entries(q.options || {})
                    .map(([key, text]) => `<label><input type="radio" name="q${q.number}" value="${escapeHtml(key)}"> <strong>${escapeHtml(key)}</strong>&nbsp;${inline(cleanOption(text))}</label>`).join('')}</div></div>`;
            }
            break;
        }
        case 'multiple_choice_multi': {
            multiSelect = true;
            const groupNumbers = [...group.numbers].sort((a, b) => a - b);
            const list = asList(group.answers);
            groupNumbers.forEach((number, index) => {
                const value = index === groupNumbers.length - 1 ? list.slice(index) : [list[index]];
                addAnswer(number, value.filter(Boolean));
            });
            const name = `q${groupNumbers.join('-')}`;
            body += `<div class="question-item"><p>${inline(group.text)}</p><div class="options">${Object.entries(group.options || {})
                .map(([key, text]) => `<label><input type="checkbox" name="${name}" value="${escapeHtml(key)}"> <strong>${escapeHtml(key)}</strong>&nbsp;${inline(cleanOption(text))}</label>`).join('')}</div></div>`;
            break;
        }
        case 'matching_headings': {
            const missing = [];
            for (const q of group.questions) {
                addAnswer(q.number, q.answer);
                if (context.paragraphLabels.has(q.paragraph)) {
                    zones.push({ number: q.number, label: q.paragraph });
                } else {
                    missing.push(q);
                }
            }
            if (group.example) {
                body += `<p class="example"><em>Example:</em> Paragraph ${escapeHtml(group.example.paragraph)} — <strong>${escapeHtml(group.example.answer)}</strong></p>`;
            }
            for (const q of missing) {
                body += `<div class="match-question-item"><p><strong>${q.number}</strong> Paragraph ${escapeHtml(q.paragraph)} <span class="match-dropzone" data-question="q${q.number}"></span></p></div>`;
            }
            body += `<div class="headings-pool"><strong>List of Headings</strong><div class="pool-items">${poolItems(group.headings || {}, 'heading', false)}</div></div>`;
            break;
        }
        case 'matching_information': {
            const given = group.questions.map((q) => q.answer);
            const letters = context.paragraphLetters.length >= 2
                ? letterRange(group.instruction, context.paragraphLetters, given)
                : letterRange(group.instruction, ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'], given);
            for (const q of group.questions) addAnswer(q.number, q.answer);
            body += `<table class="matching-table"><thead><tr><th></th>${letters.map((l) => `<th>${l}</th>`).join('')}</tr></thead><tbody>${group.questions
                .map((q) => `<tr><td><strong>${q.number}</strong> ${inline(q.text)}</td>${letters
                    .map((l) => `<td><input type="radio" name="q${q.number}" value="${l}" aria-label="${l}"></td>`).join('')}</tr>`).join('')}</tbody></table>`;
            break;
        }
        case 'matching_features':
        case 'matching_sentence_endings': {
            if (group.type === 'matching_sentence_endings') allowReuse = false;
            for (const q of group.questions) addAnswer(q.number, q.answer);
            body += group.questions.map((q) =>
                `<div class="match-question-item"><p><strong>${q.number}</strong> ${inline(q.text)} <span class="match-dropzone" data-question="q${q.number}"></span></p></div>`
            ).join('');
            const title = group.optionsTitle ? `<strong>${inline(group.optionsTitle)}</strong>` : '';
            body += `<div class="options-pool-box">${title}<div class="options-pool">${poolItems(group.options || {}, 'option', allowReuse)}</div></div>`;
            break;
        }
        case 'sentence_completion': {
            for (const q of group.questions) {
                addAnswer(q.number, q.answer);
                const known = new Set([q.number]);
                const text = blankNumbers(q.text).includes(q.number) ? q.text : `${q.text} {{${q.number}}}`;
                body += `<div class="question-item sentence-item"><p>${withBlanks(text, known)}</p></div>`;
            }
            break;
        }
        case 'short_answer': {
            for (const q of group.questions) {
                addAnswer(q.number, q.answer);
                body += `<div class="question-item"><p><strong>${q.number}</strong> ${inline(q.text)}</p><p>${gapInput(q.number)}</p></div>`;
            }
            break;
        }
        case 'summary_completion':
        case 'summary_completion_options': {
            const options = group.type === 'summary_completion_options';
            for (const [number, value] of Object.entries(group.answers || {})) addAnswer(Number(number), value);
            const known = new Set(numbers);
            let text = String(group.text ?? '');
            if (group.title) {
                const lead = `**${group.title}**`;
                if (text.startsWith(lead)) text = text.slice(lead.length).trim();
            }
            const render = options
                ? (n) => `<span class="drop-target-summary" data-question="q${n}"></span>`
                : gapInput;
            if (group.title) body += `<h4 class="block-title">${inline(group.title)}</h4>`;
            body += `<div class="summary-text">${text.split(/\n{2,}/).map((p) => `<p>${withBlanks(p, known, render)}</p>`).join('')}</div>`;
            if (options) {
                body += `<div class="options-pool-box"><div class="options-pool word-pool">${poolItems(group.options || {}, 'key', allowReuse, 'draggable-word')}</div></div>`;
            }
            break;
        }
        case 'note_completion': {
            for (const [number, value] of Object.entries(group.answers || {})) addAnswer(Number(number), value);
            const known = new Set(numbers);
            if (group.title) body += `<h4 class="block-title">${inline(group.title)}</h4>`;
            const lines = [];
            const items = (group.lines || []).map((line) => (typeof line === 'string' ? { text: line, level: 0 } : line));
            for (const segment of uncumulate(items.map((item) => item.text))) {
                const item = items[segment.index];
                if (segment.flattened) {
                    const level = Number(item.level) || 0;
                    for (const part of splitFlattened(segment.text)) {
                        lines.push(part.heading
                            ? { text: part.text, level: Math.max(level - 1, 0), heading: true }
                            : { text: part.text, level: part.sub ? level + 1 : level });
                    }
                } else {
                    for (const part of String(segment.text).split(/\s+·\s+/)) {
                        // 行首的「•」「-」是原文的项目符号，改用对应层级显示，避免重复
                        const text = part.replace(/^\s*[•·▪●■◦]\s*/, '');
                        if (!item.heading && /^\s*[-–]\s*(?=\S)/.test(text)) {
                            splitDashes(text).forEach((piece) => lines.push({ ...item, text: piece.text, level: (Number(item.level) || 0) + 1 }));
                        } else {
                            lines.push({ ...item, text });
                        }
                    }
                }
            }
            // 一行里粘在一起的几条要点拆成多行
            const expanded = lines.flatMap((line) => (line.heading ? [line] : splitGlued(line.text).map((text) => {
                // 原文自带的项目符号（▪ • ● ■）去掉，由版式统一显示；「- 」为下一级
                const sub = /^\s*[-–](?:\s+|(?=\d{4}))/.test(text);
                return { ...line, text: text.replace(/^\s*(?:[•·▪●■◦]|[-–](?=\s|\d{4}))\s*/, ''), level: sub ? Math.min((Number(line.level) || 0) + 1, 3) : line.level };
            })));
            body += `<div class="notes">${expanded.map((line) => {
                const level = Math.min(Math.max(Number(line.level) || 0, 0), 3);
                return `<div class="note-line level-${level}${line.heading ? ' note-heading' : ''}">${withBlanks(line.text, known)}</div>`;
            }).join('')}</div>`;
            break;
        }
        case 'table_completion': {
            for (const [number, value] of Object.entries(group.answers || {})) addAnswer(Number(number), value);
            const known = new Set(numbers);
            let columns = group.columns || [];
            let rows = group.rows || [];
            const filled = (cell) => String(cell ?? '').trim() !== '';
            const single = (row) => filled(row[0]) && row.slice(1).every((cell) => !filled(cell));
            const notes = [];
            // 表头误用了示例行（只有第一格有内容），真正的表头在第一行
            if (columns.length > 1 && single(columns) && rows.length && rows[0].every(filled)) {
                notes.push({ text: columns[0], level: 0 });
                columns = rows[0];
                rows = rows.slice(1);
            }
            // 只有第一格有内容、且逐行累加的行，其实是表格外的表单说明，拆成笔记
            const chain = new Set();
            for (let i = 0; i + 1 < rows.length; i++) {
                if (single(rows[i]) && single(rows[i + 1]) && String(rows[i + 1][0]).trim().startsWith(String(rows[i][0]).trim())) {
                    chain.add(i);
                    chain.add(i + 1);
                }
            }
            const chainRows = rows.filter((_, i) => chain.has(i));
            // 累加的第一行通常以示例句开头，示例已单独显示，去掉重复部分
            const example = notes.length ? String(notes[0].text).replace(/^\s*\*?Example(\s+Answer)?\*?\s*/i, '').trim() : '';
            const texts = chainRows.map((row) => row[0]);
            if (example && String(texts[0] ?? '').trim().startsWith(example)) texts.unshift(example);
            const segments = uncumulate(texts);
            if (texts[0] === example) segments.shift();
            for (const segment of segments) {
                for (const part of splitFlattened(segment.text)) notes.push({ text: part.text, level: part.heading ? 0 : part.sub ? 2 : 1, heading: part.heading });
            }
            rows = rows.filter((_, i) => !chain.has(i));
            const notesHtml = notes.length ? `<div class="notes">${notes.flatMap((line) => (line.heading ? [line] : splitGlued(line.text).map((text) => ({ ...line, text })))).map((line) => `<div class="note-line level-${line.level}${line.heading ? ' note-heading' : ''}">${withBlanks(line.text, known)}</div>`).join('')}</div>` : '';
            const first = (items) => Math.min(...items.flatMap(blankNumbers), Infinity);
            const notesFirst = first(notes.map((n) => n.text)) < first(rows.flat().concat(columns));
            const width = Math.max(columns.length, ...rows.map((r) => r.length));
            if (group.title) body += `<h4 class="block-title">${inline(group.title)}</h4>`;
            if (notesFirst) body += notesHtml;
            body += `<table class="completion-table">${columns.length ? `<thead><tr>${Array.from({ length: width }, (_, i) => `<th>${inline(columns[i] ?? '')}</th>`).join('')}</tr></thead>` : ''}<tbody>${rows
                .map((row) => `<tr>${Array.from({ length: width }, (_, i) => `<td>${tableCell(row[i] ?? '', known)}</td>`).join('')}</tr>`).join('')}</tbody></table>`;
            if (!notesFirst) body += notesHtml;
            break;
        }
        case 'flow_chart_completion': {
            for (const [number, value] of Object.entries(group.answers || {})) addAnswer(Number(number), value);
            const known = new Set(numbers);
            const steps = (group.steps || []).map((s) => decodeEntities(s)).filter((s) => !/^[\s↓→⇓▼]*$/.test(s));
            const hasBullets = steps.some((s) => /^\s*[•·▪-]\s*/.test(s));
            const boxes = [];
            for (const step of steps) {
                const bullet = /^\s*[•·▪]\s*/.test(step);
                const text = step.replace(/^\s*[•·▪]\s*/, '');
                if (!hasBullets || !bullet || !boxes.length) {
                    boxes.push({ title: hasBullets && !bullet ? text : null, lines: hasBullets && !bullet ? [] : [text] });
                } else {
                    boxes[boxes.length - 1].lines.push(text);
                }
            }
            if (group.title) body += `<h4 class="block-title">${inline(group.title)}</h4>`;
            body += `<div class="flow-chart">${boxes.map((box) =>
                `<div class="flow-box">${box.title ? `<div class="flow-title">${withBlanks(box.title, known)}</div>` : ''}${box.lines
                    .flatMap((line) => splitGlued(line))
                    .map((line) => `<div class="flow-line${box.title ? ' bullet' : ''}">${withBlanks(line, known)}</div>`).join('')}</div>`
            ).join('<div class="flow-arrow" aria-hidden="true">↓</div>')}</div>`;
            break;
        }
        case 'diagram_label_completion': {
            for (const [number, value] of Object.entries(group.answers || {})) addAnswer(Number(number), value);
            const known = new Set(numbers);
            if (group.title) body += `<h4 class="block-title">${inline(group.title)}</h4>`;
            const image = group.image ? path.basename(group.image) : '';
            if (image && fs.existsSync(path.join(BANK, 'images', image))) {
                context.images.add(image);
                body += `<figure class="diagram"><img src="content/bank/images/${encodeURIComponent(image)}" alt="Diagram"></figure>`;
            } else {
                warn(`${context.id} 缺少图片 ${group.image || '(未提供)'}`);
                body += `<p class="missing-image">（原题图片缺失）</p>`;
            }
            const letters = Object.keys(group.options || {});
            if (letters.length) {
                // 地图 / 平面图：把字母填到地点旁边 → 表格单选
                const described = Object.entries(group.options).filter(([, text]) => String(text).trim());
                if (described.length) {
                    body += `<div class="options-legend">${described.map(([key, text]) => `<p><strong>${escapeHtml(key)}</strong>&nbsp;${inline(cleanOption(text))}</p>`).join('')}</div>`;
                }
                body += `<table class="matching-table"><thead><tr><th></th>${letters.map((l) => `<th>${escapeHtml(l)}</th>`).join('')}</tr></thead><tbody>${(group.labels || []).map((label) => {
                    const text = String(label.text).replace(/\{\{\s*\d+\s*\}\}/g, '').replace(new RegExp(`^\\s*${label.number}\\s*`), '').trim();
                    return `<tr><td><strong>${label.number}</strong> ${inline(text)}</td>${letters
                        .map((l) => `<td><input type="radio" name="q${label.number}" value="${escapeHtml(l)}" aria-label="${escapeHtml(l)}"></td>`).join('')}</tr>`;
                }).join('')}</tbody></table>`;
            } else {
                body += `<div class="diagram-labels">${(group.labels || []).map((label) => {
                    const raw = String(label.text).replace(new RegExp(`^\\s*${label.number}\\s+`), '');
                    const text = blankNumbers(raw).length ? raw : `${raw} {{${label.number}}}`;
                    return `<p><strong>${label.number}</strong> ${withBlanks(text, known)}</p>`;
                }).join('')}</div>`;
            }
            break;
        }
        default:
            warn(`${context.id} 未知题型 ${group.type}`);
    }

    // 原题内容缺失（例如表格只有答案没有表身）时，保留编号答题框，保证每题都能作答
    const placed = (n) => zones.some((zone) => zone.number === n)
        || new RegExp(`name="q(?:\\d+-)*${n}(?:-\\d+)*"|data-question="q${n}"`).test(body);
    const orphans = numbers.filter((n) => !placed(n));
    if (orphans.length) {
        warn(`${context.id} 第 ${orphans.join('、')} 题缺少原题版面，已改为单独答题框`);
        body += `<p class="missing-image">（原题${group.type === 'table_completion' ? '表格' : '版面'}内容缺失，仅保留答题框）</p>`
            + orphans.map((n) => `<p><strong>${n}</strong> ${gapInput(n)}</p>`).join('');
    }

    const html = `<div class="group"><h4>${rangeLabel(numbers)}</h4>${instructionHtml(group, context)}${body}</div>`;
    return { html, numbers, answers, multiSelect, allowReuse, zones };
}

function lettersBetween(a, b) {
    const letters = [];
    for (let c = a.charCodeAt(0); c <= b.charCodeAt(0); c += 1) letters.push(String.fromCharCode(c));
    return letters;
}

/**
 * matching_features 中题干全是「Paragraph X」，或题干为空但说明是
 * 「Choose the correct heading for each paragraph / for paragraphs B–H」时，其实是段落标题匹配题。
 */
/** 题库包里有图、但题组没有引用的情况：按「文档 id + 题组首题号」补上图片。 */
const IMAGE_OVERRIDES = {
    'c7-test3-p2:20': 'c7-test3-p2-0.png',
    'c8-test2-p1:1': 'c8-test2-p1-0.png',
    'c7-test3-l3:23': 'c7-test3-p3-0.png',
};

function attachOverrideImage(group, documentID) {
    const numbers = group.questions?.map((q) => q.number) || group.numbers
        || Object.keys(group.answers || {}).map(Number) || [];
    const first = Math.min(...numbers);
    const image = IMAGE_OVERRIDES[`${documentID}:${first}`];
    return image && !group.image ? { ...group, image: `images/${image}`, imageAttached: true } : group;
}

function normalizeGroup(group, paragraphLabels) {
    const questions = group.questions || [];
    if (group.type === 'matching_features' && questions.length &&
        questions.every((q) => !String(q.text ?? '').trim()) &&
        /correct heading/i.test(group.instruction || '')) {
        const instruction = String(group.instruction);
        const range = instruction.match(/(?:paragraphs?|sections?)\s+([A-Z])\s*[-–—]+\s*([A-Z])\b/i)
            || instruction.match(/\b([A-Z])\s*[-–—]+\s*([A-Z])\b/);
        const letters = range ? lettersBetween(range[1].toUpperCase(), range[2].toUpperCase()) : [];
        const usable = letters.slice(-questions.length);
        if (usable.length === questions.length && usable.every((l) => paragraphLabels.has(l))) {
            return {
                type: 'matching_headings',
                instruction: group.instruction,
                headings: Object.fromEntries(Object.entries(group.options || {}).map(([k, v]) => [k, cleanOption(v)])),
                questions: questions.map((q, i) => ({ number: q.number, paragraph: usable[i], answer: q.answer })),
            };
        }
    }
    if (group.type === 'matching_features' && group.questions?.length &&
        group.questions.every((q) => /^(paragraph|section)\s+[A-Z]\s*$/i.test(String(q.text).trim())) &&
        group.questions.every((q) => paragraphLabels.has(String(q.text).trim().slice(-1).toUpperCase()))) {
        return {
            type: 'matching_headings',
            instruction: group.instruction,
            headings: Object.fromEntries(Object.entries(group.options || {}).map(([k, v]) => [k, cleanOption(v)])),
            questions: group.questions.map((q) => ({
                number: q.number,
                paragraph: String(q.text).trim().slice(-1).toUpperCase(),
                answer: q.answer,
            })),
        };
    }
    return group;
}


/** 「选两项」类题目的解析通常只写在第一个题号下，补给同组其他题号。 */
function shareGroupNotes(notes, groups) {
    const result = { ...notes };
    for (const group of groups) {
        if (group.type !== 'multiple_choice_multi') continue;
        const numbers = (group.numbers || []).map(String);
        const source = numbers.find((n) => result[n]);
        if (!source) continue;
        numbers.forEach((n) => { if (!result[n]) result[n] = result[source]; });
    }
    return result;
}

function buildDocument({ id, skill, part, title, category, groups, passageHtmlFor, context }) {
    const rendered = groups.map((group) => renderGroup(group, context));
    const order = [];
    const answerKey = {};
    const questionGroups = rendered.map((result, index) => {
        result.numbers.forEach((n) => {
            if (answerKey[`q${n}`]) warn(`${id} 题号 ${n} 重复`);
            answerKey[`q${n}`] = result.answers[n];
            order.push(n);
        });
        return {
            id: `g${index + 1}`,
            kind: KIND[groups[index].type] || 'other',
            questionIds: result.numbers.map((n) => `q${n}`),
            html: result.html,
            allowOptionReuse: result.allowReuse,
            multiSelect: result.multiSelect,
        };
    });
    order.sort((a, b) => a - b);
    for (let i = 1; i < order.length; i += 1) {
        if (order[i] !== order[i - 1] + 1) warn(`${id} 题号不连续：${order[i - 1]} → ${order[i]}`);
    }
    const zones = rendered.flatMap((r) => r.zones);
    return {
        id,
        skill,
        part,
        title,
        titleZh: '',
        category,
        frequency: context.frequency || 'medium',
        passageHtml: passageHtmlFor ? passageHtmlFor(zones, order) : '',
        questionGroups,
        questionOrder: order.map((n) => `q${n}`),
        questionNumbers: Object.fromEntries(order.map((n) => [`q${n}`, String(n)])),
        answerKey,
    };
}

// -----------------------------------------------------------------------------
// 阅读
// -----------------------------------------------------------------------------
/** 剑桥：c18-test1 / c18-testa-gt；其他系列（如「雅思红皮密卷 Test 1」）从标题解析。 */
function parseSetId(id, title = '') {
    const match = id.match(/^c(\d+)-test(\w+?)(-gt)?$/i);
    if (match) {
        return {
            book: Number(match[1]),
            test: match[2].toUpperCase(),
            series: `剑桥雅思 ${match[1]}`,
            cambridge: true,
            sortKey: `1-${String(match[1]).padStart(3, '0')}-${match[2]}`,
        };
    }
    const clean = String(title).replace(/\(Listening\)/i, '').trim();
    const named = clean.match(/^(.*?)\s*Test\s*(\w+)\s*$/i);
    return {
        book: null,
        test: named ? named[2].toUpperCase() : id,
        series: named ? named[1] : (clean || id),
        cambridge: false,
        sortKey: `0-${id}`,
    };
}

function displaySetTitle(id, title, module) {
    const info = parseSetId(id, title);
    return `${info.series} · Test ${info.test}${module === 'general' ? '（培训类）' : ''}`;
}

const STRIP_WORDS = (html) => html.replace(/<[^>]+>/g, ' ').replace(/&[a-z]+;/g, ' ').split(/\s+/).filter(Boolean).length;

function writeJSON(file, data) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, JSON.stringify(data));
}

// 只清理本脚本生成的内容，保留 build-extras.mjs 生成的 extras.json
for (const name of ['reading', 'listening', 'images', 'index.json']) {
    fs.rmSync(path.join(OUT, name), { recursive: true, force: true });
}
const images = new Set();
const readingIndex = [];
const readingSets = [];

/** 只导入学术类，跳过培训类（General Training）试卷 */
function isGeneralTraining(data) {
    return data.module === 'general' || /-gt(-|$)/.test(String(data.id || ''));
}
let skippedGeneral = 0;

const setFiles = fs.readdirSync(path.join(BANK, 'sets')).filter((f) => f.endsWith('.json')).sort();
for (const file of setFiles) {
    const set = JSON.parse(fs.readFileSync(path.join(BANK, 'sets', file), 'utf8'));
    if (isGeneralTraining(set)) {
        skippedGeneral += 1;
        continue;
    }
    if (!FORMATS.has(set.format)) warn(`${file} format 不是 ielts-cd-bank/1`);
    const setTitle = displaySetTitle(set.id, set.title, set.module);
    const setInfo = parseSetId(set.id, set.title);
    const passageIDs = [];

    for (const passage of set.passages) {
        const id = `${set.id}-p${passage.part}`;
        const general = set.module === 'general';
        const paragraphs = passage.text?.paragraphs || [];
        const paragraphLabels = new Set(paragraphs.map((p) => p.label).filter(Boolean));
        const paragraphLetters = paragraphs.map((p) => p.label).filter((l) => /^[A-Z]$/.test(l || ''));
        const passageLabel = general ? `Section ${passage.part}` : `Reading Passage ${passage.part}`;
        const groups = passage.groups.map((g) => attachOverrideImage(normalizeGroup(g, paragraphLabels), id));
        const rawTitle = splitHeading(passage.title).heading;
        // 标题是 A 段正文时，文章上方不再重复显示
        const titleIsParagraph = paragraphAsTitle(rawTitle) !== rawTitle;
        const { heading, sub } = splitHeading(passage.text?.heading || (titleIsParagraph ? '' : passage.title));
        const subheading = passage.text?.subheading || sub;
        const cleanTitle = paragraphAsTitle(rawTitle);
        const title = isGenericTitle(cleanTitle)
            ? (general ? `General Training Section ${passage.part}` : `Reading Passage ${passage.part}`)
            : cleanTitle;
        const context = { id, skill: 'reading', passageLabel, paragraphLabels, paragraphLetters, images, frequency: passage.frequency };

        const document = buildDocument({
            id,
            skill: 'reading',
            part: passage.part,
            title,
            category: `P${passage.part}`,
            groups,
            context,
            passageHtmlFor: (zones, order) => {
                const first = order[0];
                const last = order[order.length - 1];
                const zonesByLabel = new Map();
                zones.forEach((zone) => {
                    if (!zonesByLabel.has(zone.label)) zonesByLabel.set(zone.label, []);
                    zonesByLabel.get(zone.label).push(zone);
                });
                let html = general
                    ? `<h2>SECTION ${passage.part}</h2><p>Questions ${first}–${last}</p>`
                    : `<h2>READING PASSAGE ${passage.part}</h2><p>You should spend about 20 minutes on <strong>Questions ${first}–${last}</strong>, which are based on Reading Passage ${passage.part} below.</p>`;
                if (heading && !/^section\s*\d+$/i.test(heading)) html += `<h3>${inline(heading, { deglue: false })}</h3>`;
                if (subheading) html += `<p class="standfirst"><em>${inline(String(subheading).replace(/\*/g, ''), { deglue: false })}</em></p>`;
                paragraphs.forEach((p, index) => {
                    for (const zone of zonesByLabel.get(p.label) || []) {
                        html += `<div class="paragraph-dropzone" data-question="q${zone.number}"><span class="paragraph-label">Paragraph ${escapeHtml(zone.label)}</span><div class="dropped-items"></div></div>`;
                    }
                    const label = p.label ? `<strong>${escapeHtml(p.label)}</strong>&nbsp;` : '';
                    html += `<p data-para="${index}">${label}${inline(p.text, { deglue: false })}</p>`;
                });
                return html;
            },
        });
        writeJSON(path.join(OUT, 'reading', 'exams', `${id}.json`), document);

        const notes = shareGroupNotes(passage.explanations || {}, passage.groups);
        // 没有人工翻译时，使用 scripts/translate-bank.swift 生成的 Apple 翻译
        const machineText = (passage.translation || []).length ? null : machine.reading?.[id];
        const translation = machineText
            ? paragraphs.map((p, i) => ({ label: p.label, text: machineText[i] || '', machine: true, index: i })).filter((t) => t.text)
            : (passage.translation || []);
        if (Object.keys(notes).length || translation.length) {
            const labelIndex = new Map(paragraphs.map((p, i) => [p.label, i]));
            writeJSON(path.join(OUT, 'reading', 'explanations', `${id}.json`), {
                id,
                passageNotes: translation.map((t, i) => ({
                    label: (t.label ? `Paragraph ${t.label}` : `Paragraph ${i + 1}`) + (t.machine ? ' · Apple 翻译' : ''),
                    index: t.index ?? (t.label && labelIndex.has(t.label) ? labelIndex.get(t.label) : i),
                    text: t.text || '',
                })),
                questionNotes: Object.fromEntries(Object.entries(notes).map(([n, text]) => [`q${n}`, text])),
            });
        }

        passageIDs.push(id);
        const kinds = [...new Set(document.questionGroups.map((g) => g.kind))];
        readingIndex.push({
            id,
            title,
            titleZh: '',
            category: `P${passage.part}`,
            frequency: passage.frequency || 'medium',
            difficulty: passage.difficulty ?? null,
            questionCount: document.questionOrder.length,
            firstQuestionNumber: Number(document.questionNumbers[document.questionOrder[0]]) || 1,
            questionKinds: kinds,
            hasExplanation: Object.keys(notes).length > 0 || translation.length > 0,
            wordCount: STRIP_WORDS(document.passageHtml),
            source: setInfo.cambridge ? 'cambridge' : 'mock',
            module: set.module || 'academic',
            setId: set.id,
            setTitle,
            part: passage.part,
        });
    }

    const { book, test, series, sortKey } = setInfo;
    readingSets.push({ id: set.id, title: setTitle, module: set.module || 'academic', book, test, series, sortKey, passages: passageIDs });
}

// -----------------------------------------------------------------------------
// 听力
// -----------------------------------------------------------------------------
const listeningTests = [];
const listeningDir = path.join(BANK, 'listening');
const listeningFiles = fs.existsSync(listeningDir) ? fs.readdirSync(listeningDir).filter((f) => f.endsWith('.json')).sort() : [];
for (const file of listeningFiles) {
    const data = JSON.parse(fs.readFileSync(path.join(listeningDir, file), 'utf8'));
    if (isGeneralTraining(data)) {
        skippedGeneral += 1;
        continue;
    }
    const baseId = data.id.replace(/-listening$/, '');
    const { book, test, series, sortKey } = parseSetId(baseId, data.title);
    const title = displaySetTitle(baseId, data.title, data.module);
    const sections = [];

    for (const section of data.sections) {
        const id = `${baseId}-l${section.part}`;
        const context = { id, skill: 'listening', passageLabel: `Part ${section.part}`, paragraphLabels: new Set(), paragraphLetters: [], images };
        const document = buildDocument({
            id,
            skill: 'listening',
            part: section.part,
            title: `Part ${section.part}`,
            category: `L${section.part}`,
            groups: section.groups.map((g) => attachOverrideImage(g, id)),
            context,
        });
        const audioFile = `${id}.mp3`;
        document.audio = { url: section.audioUrl || '', file: audioFile };
        const machineLines = machine.listening?.[id] || {};
        document.transcript = (section.transcript || []).map((line, index) => ({
            en: line.en || '',
            zh: line.zh || machineLines[String(index)] || '',
            start: Number(line.start) || 0,
            end: Number(line.end) || 0,
        }));
        writeJSON(path.join(OUT, 'listening', 'exams', `${id}.json`), document);

        const numbers = document.questionOrder.map((q) => q.slice(1));
        // 新版题库包把解析放在每个 Part 内，旧版放在整套试卷上
        const shared = shareGroupNotes(section.explanations || data.explanations || {}, section.groups);
        const notes = Object.fromEntries(numbers
            .filter((n) => shared[n])
            .map((n) => [`q${n}`, shared[n]]));
        if (Object.keys(notes).length) {
            writeJSON(path.join(OUT, 'listening', 'explanations', `${id}.json`), { id, passageNotes: [], questionNotes: notes });
        }

        // 题组标题可能是占位文字 "undefined"，此时留空，界面显示题号范围
        const topicSource = section.groups.map((g) => String(g.title ?? '').trim()).find((t) => t && t !== 'undefined') || '';
        sections.push({
            id,
            part: section.part,
            topic: titleCase(String(topicSource).replace(/\*/g, '')),
            questionCount: document.questionOrder.length,
            firstQuestionNumber: Number(numbers[0]) || 1,
            questionKinds: [...new Set(document.questionGroups.map((g) => g.kind))],
            audioUrl: section.audioUrl || '',
            audioFile,
            hasTranscript: document.transcript.length > 0,
            hasExplanation: Object.keys(notes).length > 0,
        });
    }
    listeningTests.push({ id: baseId, title, module: data.module || 'academic', book, test, series, sortKey, sections });
}

// -----------------------------------------------------------------------------
// 写作（剑桥真题 Task 1 / Task 2，含图表与部分参考范文）
// -----------------------------------------------------------------------------
const writingTasks = [];
const writingDir = path.join(BANK, 'writing');
const writingFiles = fs.existsSync(writingDir) ? fs.readdirSync(writingDir).filter((f) => f.endsWith('.json')).sort() : [];
for (const file of writingFiles) {
    const data = JSON.parse(fs.readFileSync(path.join(writingDir, file), 'utf8'));
    if (isGeneralTraining(data)) {
        skippedGeneral += 1;
        continue;
    }
    const baseId = data.id.replace(/-writing$/, '');
    const info = parseSetId(baseId, data.title.replace(/\(Writing\)/i, ''));
    for (const task of data.tasks || []) {
        let image = null;
        if (task.image) {
            const name = path.basename(task.image);
            if (fs.existsSync(path.join(BANK, 'images', name))) {
                images.add(name);
                image = name;
            } else {
                warn(`${baseId} 写作 Task ${task.part} 缺少图片 ${task.image}`);
            }
        }
        writingTasks.push({
            id: `${baseId}-w${task.part}`,
            setId: baseId,
            setTitle: displaySetTitle(baseId, data.title.replace(/\(Writing\)/i, ''), data.module),
            series: info.series,
            sortKey: info.sortKey,
            module: data.module || 'academic',
            part: task.part,
            type: task.type || (task.part === 1 ? 'chart' : 'essay'),
            minWords: task.minWords || (task.part === 1 ? 150 : 250),
            prompt: decodeEntities(task.prompt || ''),
            image,
            essay: task.essay ? decodeEntities(task.essay) : null,
        });
    }
}
writingTasks.sort((a, b) => b.sortKey.localeCompare(a.sortKey, 'en', { numeric: true }) || a.part - b.part);

// -----------------------------------------------------------------------------
// 图片与索引
// -----------------------------------------------------------------------------
fs.mkdirSync(path.join(OUT, 'images'), { recursive: true });
for (const image of images) {
    fs.copyFileSync(path.join(BANK, 'images', image), path.join(OUT, 'images', image));
}

const bySortKey = (a, b) => b.sortKey.localeCompare(a.sortKey, 'en', { numeric: true });
readingSets.sort(bySortKey);
listeningTests.sort(bySortKey);
const setOrder = new Map(readingSets.map((s, i) => [s.id, i]));
readingIndex.sort((a, b) => (setOrder.get(a.setId) - setOrder.get(b.setId)) || (a.part - b.part));

writeJSON(path.join(OUT, 'index.json'), {
    format: 'ielts-cd-bank/1',
    generatedAt: new Date().toISOString(),
    reading: readingIndex,
    readingSets: readingSets.map(({ sortKey, ...rest }) => rest),
    listening: listeningTests.map(({ sortKey, ...rest }) => rest),
    writing: writingTasks.map(({ sortKey, ...rest }) => rest),
});

const questionCount = readingIndex.reduce((n, e) => n + e.questionCount, 0);
const listeningQuestions = listeningTests.reduce((n, t) => n + t.sections.reduce((m, s) => m + s.questionCount, 0), 0);
console.log(`阅读：${readingSets.length} 套，${readingIndex.length} 篇，${questionCount} 题`);
console.log(`听力：${listeningTests.length} 套，${listeningTests.reduce((n, t) => n + t.sections.length, 0)} 个 Section，${listeningQuestions} 题`);
console.log(`写作：${writingTasks.length} 题（${writingTasks.filter((t) => t.essay).length} 篇附范文）`);
console.log(`机器翻译：阅读 ${readingIndex.filter((r) => machine.reading?.[r.id]).length} 篇`);
console.log(`已跳过培训类：${skippedGeneral} 个文件`);
console.log(`图片：${images.size} 张`);
if (warnings.length) {
    console.log(`\n提示 ${warnings.length} 条：`);
    warnings.slice(0, 40).forEach((w) => console.log('  - ' + w));
    if (warnings.length > 40) console.log(`  … 另有 ${warnings.length - 40} 条`);
}
