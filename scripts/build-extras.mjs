#!/usr/bin/env node
// =============================================================================
// 将题库源文件 extras/ 中的考情数据转换为 App 使用的 Content/bank/extras.json。
//
// 用法:
//   node scripts/build-extras.mjs [题库源文件目录，默认 bank-source/]
//
// 导入：机经考情（重考次数、最近考到、练习人数、平均正确率）、考试回忆、写作题目、口语题库。
// 不导入：排行榜（其他用户的用户名与头像）和账号个人统计。
// 需先运行 scripts/build-bank.mjs（用于把机经题目关联到 App 内已有的篇目）。
// =============================================================================
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const BANK = path.resolve(process.argv[2] || path.join(ROOT, 'bank-source'));
const EXTRAS = path.join(BANK, 'extras');
const CONTENT = path.join(ROOT, 'IELTSCDPractice', 'Content');
const OUT = path.join(CONTENT, 'bank', 'extras.json');

const readJSON = (file) => JSON.parse(fs.readFileSync(file, 'utf8'));
const readLines = (file) => fs.readFileSync(file, 'utf8').split('\n').filter(Boolean).map((line) => JSON.parse(line));

if (!fs.existsSync(EXTRAS)) {
    console.error(`ERROR: 找不到 ${EXTRAS}`);
    process.exit(1);
}

// -----------------------------------------------------------------------------
// App 内已有篇目，用于关联
// -----------------------------------------------------------------------------
const bankIndex = readJSON(path.join(CONTENT, 'bank', 'index.json'));

const STOP = new Set(['the', 'a', 'an', 'of', 'and', 'in', 'on', 'to', 'for', 'is', 'are', 'how', 'why', 'what', 'its', 'with']);
const normalize = (text) => String(text ?? '').toLowerCase().replace(/[‘’']/g, '').replace(/[^a-z0-9]+/g, ' ').trim();
const tokens = (text) => normalize(text).split(' ').filter((t) => t && !STOP.has(t))
    .map((t) => (t.length > 3 && t.endsWith('s') ? t.slice(0, -1) : t));

function similarity(a, b) {
    const ta = new Set(tokens(a));
    const tb = new Set(tokens(b));
    if (!ta.size || !tb.size) return 0;
    let common = 0;
    ta.forEach((t) => { if (tb.has(t)) common += 1; });
    return common / (ta.size + tb.size - common);
}

const readingCandidates = bankIndex.reading.filter((e) => e.module !== 'general')
    .map((e) => ({ id: e.id, title: e.title, part: e.part }));
const listeningCandidates = bankIndex.listening.filter((t) => t.module !== 'general')
    .flatMap((t) => t.sections.map((s) => ({ id: s.id, title: s.topic, part: s.part })));

function bestMatch(title, candidates, part) {
    let best = null;
    let score = 0;
    if (!normalize(title)) return null;
    for (const candidate of candidates) {
        if (part && candidate.part && candidate.part !== part) continue;
        if (!normalize(candidate.title)) continue;
        const exact = normalize(candidate.title) === normalize(title);
        const value = exact ? 1 : similarity(title, candidate.title);
        if (value > score) {
            score = value;
            best = candidate;
        }
    }
    return score >= 0.7 ? best.id : null;
}

// -----------------------------------------------------------------------------
// 机经考情
// -----------------------------------------------------------------------------
const jj = readJSON(path.join(EXTRAS, '机经命中统计.json'));

function jijingItem(item, skill) {
    const part = Number(item.partType) || null;
    const title = String(item.title ?? '').trim();
    const match = skill === 'reading' ? bestMatch(title, readingCandidates, part)
        : skill === 'listening' ? bestMatch(title, listeningCandidates, part) : null;
    return {
        id: String(item.subjectId),
        code: String(item.jjCode ?? ''),
        skill,
        part: skill === 'writing' ? Number(item.writingPart) || null : part,
        title,
        topic: item.topicName || item.writingTopicName || '',
        difficulty: item.difficulty ?? null,
        practiceCount: Number(item.practiceNum) || 0,
        correctRate: item.correctRate ?? null,
        retestCount: Number(item.retestTotalCount) || 0,
        lastHitDate: item.lastHitDate || null,
        questionTypes: item.qsTypeList || [],
        question: item.writingQuestion || null,
        match,
    };
}

// 只保留学术类：去掉培训类书信题（话题为「书信（G类）」）
const jijing = [
    ...jj.listening.map((item) => jijingItem(item, 'listening')),
    ...jj.reading.map((item) => jijingItem(item, 'reading')),
    ...jj.writing.map((item) => jijingItem(item, 'writing')),
].filter((item) => !/G类|书信/.test(item.topic));
const jijingByID = new Map(jijing.map((item) => [item.id, item]));
const recentHits = (jj.recentHits || []).map((item) => String(item.subjectId)).filter((id) => jijingByID.has(id));

// -----------------------------------------------------------------------------
// 考试回忆
// -----------------------------------------------------------------------------
const STAR = { 一星: 1, 二星: 2, 三星: 3, 四星: 4, 五星: 5 };

function parseContent(content) {
    const fields = {};
    const extra = [];
    for (const line of String(content ?? '').split('\n').map((l) => l.trim()).filter(Boolean)) {
        const match = line.match(/^(主题|题型|关键词|阅读评级|难度)[:：]\s*(.*)$/);
        if (match) fields[match[1]] = match[2].trim();
        else extra.push(line);
    }
    return { fields, note: extra.join('\n') };
}

const exams = readLines(path.join(EXTRAS, '考试回忆.jsonl')).map((record) => {
    const listening = (record.listenedSections || []).map((section) => {
        const { fields, note } = parseContent(section.content);
        const jjID = section.jiJingProQuestionCode ? String(section.jiJingProQuestionCode) : null;
        const jjItem = jjID ? jijingByID.get(jjID) : null;
        return {
            part: Number(String(section.partType).replace(/\D/g, '')) || null,
            code: section.code || null,
            theme: fields['主题'] || jjItem?.title || null,
            questionTypes: fields['题型'] || null,
            keywords: fields['关键词'] || null,
            note: note || null,
            image: section.picUrl || null,
            jijing: jjItem ? jjID : null,
            match: jjItem?.match || (fields['主题'] ? bestMatch(fields['主题'], listeningCandidates) : null),
        };
    });
    const reading = (record.passages || []).map((passage) => {
        const { fields, note } = parseContent(passage.content);
        const theme = fields['主题'] || null;
        const jjID = passage.jiJingProQuestionCode ? String(passage.jiJingProQuestionCode) : null;
        const jjItem = jjID ? jijingByID.get(jjID) : null;
        const part = Number(String(passage.partType).replace(/\D/g, '')) || null;
        return {
            part,
            code: passage.code || null,
            theme: theme || jjItem?.title || null,
            rating: STAR[fields['阅读评级']] || null,
            questionTypes: fields['题型'] || null,
            note: note || null,
            image: passage.picUrl || null,
            jijing: jjItem ? jjID : null,
            match: jjItem?.match || (theme ? bestMatch(theme, readingCandidates, part) : null),
        };
    });
    const writing = (record.tasks || []).map((task) => {
        const jjID = task.jiJingProQuestionCode ? String(task.jiJingProQuestionCode) : null;
        return {
            task: Number(String(task.partType).replace(/\D/g, '')) || null,
            question: task.writingQuestion || null,
            note: task.content || null,
            image: task.taskPicUrl || null,
            jijing: jjID && jijingByID.has(jjID) ? jjID : null,
        };
    });
    return {
        id: String(record.memoryId),
        date: record.examDate,
        place: record.examPlace || '',
        module: record.examType === 'G' ? 'general' : 'academic',
        listening,
        reading,
        writing,
    };
}).filter((exam) => exam.module !== 'general' && (exam.listening.length || exam.reading.length || exam.writing.length))
    .sort((a, b) => b.date.localeCompare(a.date));

// -----------------------------------------------------------------------------
// 口语
// -----------------------------------------------------------------------------
const CATALOG = { 1: '人物', 2: '事物', 3: '事件', 4: '地点' };

function speakingQuestion(q, index, topicID) {
    return {
        id: String(q.questionId ?? `${topicID}-${index}`),
        part: Number(q.part) || 1,
        text: String(q.question ?? '').trim(),
        sample: String(q.answerPreview ?? q.sampleAnswer ?? '').trim(),
        audio: (q.audio || []).filter((a) => a && a.url).map((a) => ({ accent: a.accent || '英音', url: a.url })),
    };
}

function speakingTopic(topic, part) {
    const id = String(topic.topicId);
    return {
        id,
        name: topic.topic ?? topic.topicName,
        part,
        category: CATALOG[topic.catalog ?? topic.category] || '',
        recentExamCount: Number(topic.examFrequency ?? topic.recentExamCount) || 0,
        practiceText: topic.practiceCount ?? topic.oralNums ?? '',
        questions: (topic.questions || []).map((q, i) => speakingQuestion(q, i, id)).filter((q) => q.text),
    };
}

// 新版题库包：speaking/part1.json + part2-3.json；旧版：extras/口语题库.json
let speakingTopics = [];
let season = '';
const speakingDir = path.join(BANK, 'speaking');
if (fs.existsSync(path.join(speakingDir, 'part1.json'))) {
    const part1 = readJSON(path.join(speakingDir, 'part1.json'));
    const part23 = readJSON(path.join(speakingDir, 'part2-3.json'));
    season = part1.season || '';
    speakingTopics = [
        ...part1.topics.map((t) => speakingTopic(t, 1)),
        ...part23.topics.map((t) => speakingTopic(t, 2)),
    ];
} else {
    const raw = readJSON(path.join(EXTRAS, '口语题库.json'));
    season = raw.topics[0]?.timeTag || '';
    speakingTopics = raw.topics.map((t) => speakingTopic(t, t.part === 0 ? 1 : 2));
}
const speaking = {
    season,
    topics: speakingTopics,
    examiner: readJSON(path.join(EXTRAS, '口语考试语料.json')).map((line) => ({ text: line.corpusText, audio: line.corpusUrl })),
};

// -----------------------------------------------------------------------------
// 写作：机经写作题 + 考试回忆中出现、但不在机经里的题目
// -----------------------------------------------------------------------------
const writingSeen = new Set(jijing.filter((i) => i.skill === 'writing').map((i) => normalize(i.question)));
const extraWriting = [];
for (const exam of exams) {
    for (const task of exam.writing) {
        if (!task.question || task.jijing || writingSeen.has(normalize(task.question))) continue;
        writingSeen.add(normalize(task.question));
        extraWriting.push({
            id: `memory-${exam.id}-${task.task}`,
            code: '',
            skill: 'writing',
            part: task.task,
            title: task.question.split(/[.?!]/)[0].slice(0, 40),
            topic: '考试回忆',
            difficulty: null,
            practiceCount: 0,
            correctRate: null,
            retestCount: 0,
            lastHitDate: exam.date,
            questionTypes: [],
            question: task.question,
            match: null,
        });
    }
}

const extras = {
    generatedAt: new Date().toISOString(),
    jijing: [...jijing, ...extraWriting],
    recentHits,
    exams,
    speaking,
};
fs.writeFileSync(OUT, JSON.stringify(extras));

const matched = (skill) => jijing.filter((i) => i.skill === skill && i.match).length;
const count = (skill) => jijing.filter((i) => i.skill === skill).length;
console.log(`机经：听力 ${count('listening')}（已关联 ${matched('listening')}）、阅读 ${count('reading')}（已关联 ${matched('reading')}）、写作 ${count('writing') + extraWriting.length}`);
console.log(`考试回忆：${exams.length} 场（${exams.at(-1)?.date} – ${exams[0]?.date}）`);
console.log(`口语：${speaking.topics.length} 个话题，${speaking.topics.reduce((n, t) => n + t.questions.length, 0)} 道题目`);
