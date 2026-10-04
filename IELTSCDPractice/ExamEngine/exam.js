/*
 * IELTS CD Practice — 机考引擎
 *
 * 原生端通过 ExamEngine.start(config) 传入题目；作答过程中通过
 * window.webkit.messageHandlers.exam 回传草稿、提交、退出等事件。
 *
 * config = {
 *   mode: 'test' | 'review' | 'study',
 *   parts: [{ exam, explanation }],
 *   timer: { kind: 'countdown' | 'countup' | 'none', limit: 秒 },
 *   candidateId, preferences: { contrast, textSize, split, hideTimer },
 *   draft: { parts: [{ answers }], highlights, elapsed, currentPart } | null,
 *   review: { parts: [{ answers }], results } | null,
 *   actions: { retry, next }   // 复盘卡片上显示哪些按钮
 * }
 */
(function () {
    'use strict';

    const bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.exam;
    function post(type, payload) {
        if (bridge) {
            bridge.postMessage({ type: type, payload: payload === undefined ? null : payload });
        } else {
            console.log('[exam → native]', type, payload);
        }
    }

    const $ = (id) => document.getElementById(id);
    const workspace = $('workspace');
    const navParts = $('nav-parts');
    const timerButton = $('timer');
    const timerText = $('timer-text');

    const state = {
        mode: 'test',
        config: null,
        parts: [],
        currentPart: 0,
        current: null,            // { part, qid }
        timer: { kind: 'countdown', limit: 3600, elapsed: 0, paused: false, hidden: false, last: 0, handle: 0 },
        results: null,
        highlightSeq: 0,
        draftTimer: 0,
        submitted: false,
        waitingStart: false,      // 正在显示考试说明页，计时尚未开始
        reviews: new Set(),       // 标记为 Review 的题目：「部分序号:题号」
        listeningReview: { started: false, elapsed: 0 },
        preferences: { contrast: 'standard', textSize: 'regular', split: 0.5, hideTimer: false },
    };

    /** 听完录音后的检查时间（与官方机考一致为 2 分钟） */
    const REVIEW_SECONDS = 120;

    /** 模考：严格按官方规则（录音只播放一次、不能暂停、计时不可暂停） */
    function isStrict() {
        return !!(state.config && state.config.strict) && state.mode === 'test';
    }

    function isStrictListening() {
        return isStrict() && state.parts.some((part) => part.listening);
    }

    // ------------------------------------------------------------------
    // 工具
    // ------------------------------------------------------------------
    function el(tag, className, text) {
        const node = document.createElement(tag);
        if (className) node.className = className;
        if (text != null) node.textContent = text;
        return node;
    }

    function cleanText(value) {
        return String(value == null ? '' : value).replace(/\s+/g, ' ').trim();
    }

    function same(a, b) {
        return cleanText(a).toLowerCase() === cleanText(b).toLowerCase();
    }

    function includesValue(list, value) {
        return (list || []).some((item) => same(item, value));
    }

    function toast(message, duration) {
        const node = $('toast');
        node.textContent = message;
        node.classList.add('show');
        clearTimeout(toast.timer);
        toast.timer = setTimeout(() => node.classList.remove('show'), duration || 1800);
    }

    function itemValue(item) {
        const d = item.dataset;
        return cleanText(d.heading || d.option || d.value || d.key || d.word || item.textContent);
    }

    function shortLabel(item) {
        const value = itemValue(item);
        const text = cleanText(item.textContent);
        return text || value;
    }

    // ------------------------------------------------------------------
    // 构建题目
    // ------------------------------------------------------------------
    function sanitize(root) {
        root.querySelectorAll('script, style, link, meta, iframe, object, embed').forEach((node) => node.remove());
        root.querySelectorAll('*').forEach((node) => {
            for (const attr of Array.from(node.attributes)) {
                if (/^on/i.test(attr.name)) node.removeAttribute(attr.name);
            }
            if (node.tagName === 'A' && node.hasAttribute('href')) {
                node.removeAttribute('href');
            }
        });
        // 宽表格在分栏中横向滚动，避免被裁切
        root.querySelectorAll('table').forEach((table) => {
            if (table.parentElement && table.parentElement.classList.contains('table-scroll')) return;
            const wrapper = document.createElement('div');
            wrapper.className = 'table-scroll';
            table.parentNode.insertBefore(wrapper, table);
            wrapper.appendChild(table);
        });
        root.querySelectorAll('img').forEach((img) => {
            const src = img.getAttribute('src') || '';
            if (/^media\//.test(src)) img.setAttribute('src', 'content/reading/' + src);
            img.removeAttribute('loading');
            img.setAttribute('draggable', 'false');
        });
    }

    function namespaceIds(root, prefix) {
        root.querySelectorAll('[id]').forEach((node) => { node.id = prefix + node.id; });
        root.querySelectorAll('label[for]').forEach((node) => node.setAttribute('for', prefix + node.getAttribute('for')));
    }

    // ------------------------------------------------------------------
    // 输入限制：与官方机考一致，只能输入英文，没有拼写检查、自动纠错、自动大写和输入预测
    // ------------------------------------------------------------------
    function lockTextInput(field) {
        field.setAttribute('autocomplete', 'off');
        field.setAttribute('autocorrect', 'off');
        field.setAttribute('autocapitalize', 'off');
        field.setAttribute('spellcheck', 'false');
        field.setAttribute('writingsuggestions', 'false');
        field.setAttribute('data-gramm', 'false');
        field.setAttribute('inputmode', 'text');
        field.setAttribute('lang', 'en');
    }

    /** 英文键盘可以输入的字符：ASCII 可打印字符、换行，以及 £ € ° */
    const DISALLOWED = /[^\x20-\x7E\n\t£€°]/g;
    const SMART_PUNCTUATION = [[/[‘’‚‛′]/g, "'"], [/[“”„‟″]/g, '"'], [/[–—−]/g, '-'], [/…/g, '...'], [/\u00A0/g, ' ']];

    function englishOnly(text) {
        let value = String(text || '');
        SMART_PUNCTUATION.forEach(([pattern, replacement]) => { value = value.replace(pattern, replacement); });
        return value.replace(DISALLOWED, '');
    }

    function isTextField(node) {
        return !!(node && node.matches && node.matches('input.gap, textarea.essay-input, #note-text'));
    }

    let composing = false;
    let warnedKeyboard = 0;

    function warnKeyboard() {
        const now = Date.now();
        if (now - warnedKeyboard < 4000) return;
        warnedKeyboard = now;
        toast('Please use the English keyboard. 请切换到英文键盘输入', 2600);
    }

    /** 去掉非英文字符，并保持光标位置 */
    function sanitizeField(field) {
        const before = field.value;
        const cleaned = englishOnly(before);
        if (cleaned === before) return false;
        const caret = field.selectionStart == null ? cleaned.length : englishOnly(before.slice(0, field.selectionStart)).length;
        field.value = cleaned;
        try { field.setSelectionRange(caret, caret); } catch (error) { /* 部分输入框不支持 */ }
        return true;
    }

    document.addEventListener('compositionstart', (event) => {
        if (!isTextField(event.target)) return;
        composing = true;
        warnKeyboard();
    }, true);

    document.addEventListener('compositionend', (event) => {
        if (!isTextField(event.target)) return;
        composing = false;
        if (sanitizeField(event.target)) event.target.dispatchEvent(new Event('input', { bubbles: true }));
    }, true);

    document.addEventListener('beforeinput', (event) => {
        if (!isTextField(event.target) || composing || event.isComposing) return;
        const data = event.data || (event.dataTransfer && event.dataTransfer.getData('text/plain')) || '';
        if (!data) return;
        // 自动替换与输入预测（insertReplacementText）一律拦截
        if (event.inputType === 'insertReplacementText') {
            event.preventDefault();
            return;
        }
        const cleaned = englishOnly(data);
        if (cleaned === data) return;
        event.preventDefault();
        if (data.replace(DISALLOWED, '') !== data && cleaned.length < data.length) warnKeyboard();
        if (cleaned) document.execCommand('insertText', false, cleaned);
    }, true);

    // 兜底：粘贴、听写等未经过 beforeinput 的输入
    document.addEventListener('input', (event) => {
        if (!isTextField(event.target) || composing || event.isComposing) return;
        if (sanitizeField(event.target)) warnKeyboard();
    }, true);

    function buildPart(partConfig, index) {
        if (partConfig.exam && partConfig.exam.skill === 'writing') return buildWritingPart(partConfig, index);
        const exam = partConfig.exam;
        const view = el('div', 'part-view');
        view.dataset.part = String(index);

        const passage = el('section', 'pane passage');
        passage.dataset.pane = 'passage';
        passage.innerHTML = exam.passageHtml || '';

        const divider = el('div', 'divider');
        divider.innerHTML = '<div class="divider-handle"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><polyline points="8 7 3 12 8 17"></polyline><polyline points="16 7 21 12 16 17"></polyline><line x1="3" y1="12" x2="21" y2="12"></line></svg></div>';

        const questions = el('section', 'pane questions');
        questions.dataset.pane = 'questions';
        const header = el('div', 'questions-header');
        questions.appendChild(header);
        (exam.questionGroups || []).forEach((group, groupIndex) => {
            const wrap = el('section', 'question-block');
            wrap.dataset.group = String(groupIndex);
            wrap.innerHTML = group.html || '';
            questions.appendChild(wrap);
        });

        view.append(passage, divider, questions);
        workspace.appendChild(view);

        sanitize(view);
        namespaceIds(view, 'p' + index + '-');

        const listening = exam.skill === 'listening';
        // 单独练习 Part 2 时也显示「Part 2」
        const label = Number(exam.part) || Number(String(exam.category || '').replace(/^\D+/, '')) || index + 1;
        if (listening) view.classList.add('listening');
        const part = {
            index,
            exam,
            listening,
            label,
            audioSrc: partConfig.audio || (exam.audio && exam.audio.url) || '',
            transcript: exam.transcript || [],
            explanation: partConfig.explanation || null,
            view,
            passage,
            questions,
            header,
            order: exam.questionOrder || [],
            numbers: exam.questionNumbers || {},
            groupOf: new Map(),
            controls: new Map(),
            zones: new Map(),
            multiGroups: [],
        };
        (exam.questionGroups || []).forEach((group, groupIndex) => {
            (group.questionIds || []).forEach((qid) => part.groupOf.set(qid, groupIndex));
        });

        hydrateControls(part);
        setUpDivider(divider, view);
        return part;
    }

    /*
     * 写作（与官方机考 Writing 一致）：左侧为题目与图表，右侧为作答框，
     * 作答框下方显示 Word count；底部导航只有 Part 1 / Part 2。
     * exam = { id, skill: 'writing', part, prompt, image, minWords, essay }
     */
    function buildWritingPart(partConfig, index) {
        const exam = partConfig.exam;
        const view = el('div', 'part-view writing');
        view.dataset.part = String(index);

        const passage = el('section', 'pane passage task-pane');
        passage.dataset.pane = 'passage';
        const prompt = el('div', 'task-prompt');
        String(exam.prompt || '').split(/\n{2,}/).map(cleanText).filter(Boolean)
            .forEach((paragraph) => prompt.appendChild(el('p', null, paragraph)));
        passage.appendChild(prompt);
        if (exam.image) {
            const figure = el('figure', 'diagram task-figure');
            const img = el('img');
            img.src = exam.image;
            img.alt = 'Task ' + exam.part;
            img.setAttribute('draggable', 'false');
            figure.appendChild(img);
            passage.appendChild(figure);
        }

        const divider = el('div', 'divider');
        divider.innerHTML = '<div class="divider-handle"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><polyline points="8 7 3 12 8 17"></polyline><polyline points="16 7 21 12 16 17"></polyline><line x1="3" y1="12" x2="21" y2="12"></line></svg></div>';

        const questions = el('section', 'pane questions answer-pane');
        questions.dataset.pane = 'questions';
        const header = el('div', 'questions-header');
        const textarea = el('textarea', 'essay-input');
        textarea.dataset.q = 'essay';
        lockTextInput(textarea);
        textarea.setAttribute('aria-label', 'Part ' + exam.part + ' answer');
        const count = el('div', 'word-count', 'Word count: 0');
        questions.append(header, textarea, count);

        view.append(passage, divider, questions);
        workspace.appendChild(view);
        sanitize(view);

        const part = {
            index,
            exam,
            writing: true,
            listening: false,
            label: Number(exam.part) || index + 1,
            minWords: Number(exam.minWords) || (Number(exam.part) === 1 ? 150 : 250),
            explanation: null,
            transcript: [],
            view,
            passage,
            questions,
            header,
            textarea,
            wordCount: count,
            order: ['essay'],
            numbers: { essay: 'Part ' + (Number(exam.part) || index + 1) },
            groupOf: new Map(),
            controls: new Map(),
            zones: new Map(),
            multiGroups: [],
        };
        part.controls.set('essay', { type: 'essay', el: textarea });
        textarea.addEventListener('input', () => {
            updateWordCount(part);
            answerChanged(part, 'essay');
        });
        setUpDivider(divider, view);
        return part;
    }

    function countWords(text) {
        const trimmed = String(text || '').trim();
        return trimmed ? trimmed.split(/\s+/).length : 0;
    }

    function updateWordCount(part) {
        if (part.writing) part.wordCount.textContent = 'Word count: ' + countWords(part.textarea.value);
    }

    function numberOf(part, qid) {
        return part.numbers[qid] || qid.replace(/^q/, '');
    }

    function registerControl(part, qid, control) {
        if (!part.order.includes(qid)) return;
        if (!part.controls.has(qid)) part.controls.set(qid, control);
    }

    function qidFromName(name) {
        const match = /^(q\d+)(?:_input)?$/i.exec(String(name || '').trim());
        return match ? match[1].toLowerCase() : null;
    }

    function hydrateControls(part) {
        const view = part.view;
        const prefix = 'p' + part.index + '_';

        // 文本填空
        view.querySelectorAll('input').forEach((input) => {
            const type = (input.getAttribute('type') || 'text').toLowerCase();
            if (type !== 'text' && type !== 'search' && type !== '') return;
            const qid = qidFromName(input.getAttribute('name')) || qidFromName((input.id || '').replace(/^p\d+-/, '')) ||
                qidFromName(input.dataset.question);
            if (!qid) return;
            input.removeAttribute('data-answer');
            input.removeAttribute('value');
            input.value = '';
            input.className = 'gap';
            input.type = 'text';
            input.name = prefix + qid;
            input.dataset.q = qid;
            input.placeholder = numberOf(part, qid);
            lockTextInput(input);
            hideInlineNumber(input, numberOf(part, qid));
            registerControl(part, qid, { type: 'gap', el: input });
        });

        // 下拉选择
        view.querySelectorAll('select').forEach((select) => {
            const qid = qidFromName(select.getAttribute('name')) || qidFromName((select.id || '').replace(/^p\d+-/, ''));
            if (!qid) return;
            select.classList.add('gap-select');
            select.name = prefix + qid;
            select.dataset.q = qid;
            select.value = '';
            registerControl(part, qid, { type: 'select', el: select });
        });

        // 单选（含表格式匹配）
        const radiosByQ = new Map();
        view.querySelectorAll('input[type="radio"]').forEach((radio) => {
            const qid = qidFromName(radio.getAttribute('name'));
            if (!qid) return;
            radio.checked = false;
            radio.name = prefix + qid;
            radio.dataset.q = qid;
            if (!radiosByQ.has(qid)) radiosByQ.set(qid, []);
            radiosByQ.get(qid).push(radio);
            const label = radio.closest('label');
            if (label) label.classList.add('choice-option');
        });
        radiosByQ.forEach((radios, qid) => registerControl(part, qid, { type: 'radio', els: radios }));

        // 复选（选出 N 个字母）
        part.exam.questionGroups.forEach((group, groupIndex) => {
            if (!group.multiSelect) return;
            const wrap = part.questions.querySelector('.question-block[data-group="' + groupIndex + '"]');
            if (!wrap) return;
            const boxes = Array.from(wrap.querySelectorAll('input[type="checkbox"]'));
            if (!boxes.length) return;
            const entry = { groupIndex, qids: group.questionIds.slice(), boxes };
            boxes.forEach((box) => {
                box.checked = false;
                box.name = prefix + 'g' + groupIndex;
                box.dataset.group = String(groupIndex);
                const label = box.closest('label');
                if (label) label.classList.add('choice-option');
            });
            part.multiGroups.push(entry);
            group.questionIds.forEach((qid) => registerControl(part, qid, { type: 'multi', group: entry }));
        });

        hydrateDragAndDrop(part);
    }

    /** 官方界面中题号显示在答题框内，隐藏紧挨在答题框前的加粗题号。 */
    function hideInlineNumber(input, number) {
        let node = input.previousSibling;
        while (node && node.nodeType === Node.TEXT_NODE && !node.textContent.trim()) node = node.previousSibling;
        if (!node) return;
        if (node.nodeType === Node.ELEMENT_NODE && /^(STRONG|B)$/.test(node.tagName) &&
            cleanText(node.textContent) === String(number)) {
            node.classList.add('qnum-inline-hidden');
        } else if (node.nodeType === Node.TEXT_NODE) {
            // 纯文本题号：「based in 8 <input>」
            const pattern = new RegExp('(^|\\s)' + String(number).replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\s*$');
            if (pattern.test(node.textContent)) {
                node.textContent = node.textContent.replace(pattern, '$1');
            }
        }
    }

    // ------------------------------------------------------------------
    // 拖拽题（指针拖动 + 点选放置，触控与触控板通用）
    // ------------------------------------------------------------------
    function hydrateDragAndDrop(part) {
        const view = part.view;
        const items = new Set();
        view.querySelectorAll('[draggable="true"], .drag-item, .draggable-word').forEach((node) => {
            if (node.closest('.dnd-zone')) return;
            if (node.tagName === 'IMG') return;
            items.add(node);
        });

        items.forEach((item) => {
            const groupWrap = item.closest('.question-block');
            const groupIndex = groupWrap ? Number(groupWrap.dataset.group) : -1;
            const group = part.exam.questionGroups[groupIndex] || {};
            item.classList.add('dnd-item');
            item.setAttribute('draggable', 'false');
            item.dataset.dndValue = itemValue(item);
            item.dataset.dndGroup = String(groupIndex);
            item.dataset.dndReuse = (group.allowOptionReuse || item.dataset.clone === 'true') ? '1' : '0';
            const pool = item.parentElement;
            if (pool && !pool.classList.contains('dnd-pool')) {
                pool.classList.add('dnd-pool');
                const labels = Array.from(pool.children).map((child) => cleanText(child.textContent).length);
                const average = labels.reduce((a, b) => a + b, 0) / Math.max(labels.length, 1);
                if (average > 28 || pool.classList.contains('pool-vertical')) pool.classList.add('vertical');
            }
        });

        view.querySelectorAll('[data-question]').forEach((zone) => {
            if (/^(INPUT|SELECT|TEXTAREA)$/.test(zone.tagName)) return;
            if (!/dropzone|drop-target/.test(zone.className)) return;
            const qid = qidFromName(zone.dataset.question);
            if (!qid || !part.order.includes(qid)) return;
            zone.classList.add('dnd-zone');
            zone.dataset.q = qid;
            zone.dataset.number = numberOf(part, qid);
            zone.dataset.dndGroup = String(part.groupOf.has(qid) ? part.groupOf.get(qid) : -1);
            const holder = zone.querySelector('.dropped-items');
            if (holder) holder.dataset.number = numberOf(part, qid);
            Array.from((holder || zone).childNodes).forEach((child) => {
                if (child.nodeType === Node.TEXT_NODE && !child.textContent.trim()) child.remove();
            });
            part.zones.set(qid, zone);
            registerControl(part, qid, { type: 'zone', el: zone });
        });
    }

    function zoneHolder(zone) {
        return zone.querySelector('.dropped-items') || zone;
    }

    function placedChip(zone) {
        return zoneHolder(zone).querySelector('.dnd-item.placed');
    }

    function sourceItemFor(part, groupIndex, value) {
        const candidates = part.view.querySelectorAll('.dnd-item:not(.placed)[data-dnd-group="' + groupIndex + '"]');
        for (const candidate of candidates) {
            if (same(candidate.dataset.dndValue, value)) return candidate;
        }
        for (const candidate of part.view.querySelectorAll('.dnd-item:not(.placed)')) {
            if (same(candidate.dataset.dndValue, value)) return candidate;
        }
        return null;
    }

    function clearZone(part, zone, silent) {
        const chip = placedChip(zone);
        if (!chip) return;
        const source = chip.__source;
        chip.remove();
        if (source) source.classList.remove('used');
        zone.classList.remove('filled');
        if (!silent) answerChanged(part, zone.dataset.q);
    }

    function placeInZone(part, sourceItem, zone, silent) {
        const value = sourceItem.dataset.dndValue;
        const origin = sourceItem.classList.contains('placed') ? sourceItem.closest('.dnd-zone') : null;
        const source = sourceItem.classList.contains('placed') ? sourceItem.__source : sourceItem;
        if (origin === zone) return;
        if (origin) clearZone(part, origin, true);
        clearZone(part, zone, true);

        const chip = el('span', 'dnd-item placed', source ? shortLabel(source) : value);
        chip.dataset.dndValue = value;
        chip.dataset.dndGroup = zone.dataset.dndGroup;
        chip.__source = source;
        zoneHolder(zone).appendChild(chip);
        zone.classList.add('filled');
        if (source && source.dataset.dndReuse !== '1') source.classList.add('used');
        if (!silent) {
            if (origin) answerChanged(part, origin.dataset.q);
            answerChanged(part, zone.dataset.q);
        }
    }

    function compatible(item, zone) {
        const a = item.dataset.dndGroup;
        const b = zone.dataset.dndGroup;
        return a === '-1' || b === '-1' || a === b;
    }

    const drag = { active: null, tapSelected: null };

    function partOf(node) {
        const view = node && node.closest ? node.closest('.part-view') : null;
        return view ? state.parts[Number(view.dataset.part)] : null;
    }

    function setTapSelected(item) {
        if (drag.tapSelected) drag.tapSelected.classList.remove('tap-selected');
        document.querySelectorAll('.dnd-zone.awaiting').forEach((zone) => zone.classList.remove('awaiting'));
        drag.tapSelected = item;
        if (!item) return;
        item.classList.add('tap-selected');
        const part = partOf(item);
        if (part) {
            part.zones.forEach((zone) => {
                if (compatible(item, zone)) zone.classList.add('awaiting');
            });
        }
    }

    function targetAt(x, y) {
        const node = document.elementFromPoint(x, y);
        if (!node) return null;
        return node.closest('.dnd-zone') || node.closest('.dnd-pool');
    }

    function autoScroll(x, y) {
        const node = document.elementFromPoint(x, y);
        const pane = node && node.closest('.pane');
        if (!pane) return;
        const rect = pane.getBoundingClientRect();
        const edge = 56;
        if (y < rect.top + edge) pane.scrollTop -= 14;
        else if (y > rect.bottom - edge) pane.scrollTop += 14;
    }

    document.addEventListener('pointerdown', (event) => {
        if (state.mode !== 'test') return;
        const item = event.target.closest && event.target.closest('.dnd-item');
        if (!item || !item.closest('.part-view')) return;
        drag.active = {
            item,
            pointerId: event.pointerId,
            startX: event.clientX,
            startY: event.clientY,
            started: false,
            ghost: null,
            hover: null,
        };
    });

    document.addEventListener('pointermove', (event) => {
        const active = drag.active;
        if (!active || event.pointerId !== active.pointerId) return;
        const dx = event.clientX - active.startX;
        const dy = event.clientY - active.startY;
        if (!active.started) {
            if (Math.hypot(dx, dy) < 6) return;
            active.started = true;
            setTapSelected(null);
            const rect = active.item.getBoundingClientRect();
            const ghost = active.item.cloneNode(true);
            ghost.classList.add('dnd-ghost');
            ghost.classList.remove('used', 'tap-selected');
            ghost.style.width = rect.width + 'px';
            active.offsetX = event.clientX - rect.left;
            active.offsetY = event.clientY - rect.top;
            document.body.appendChild(ghost);
            active.ghost = ghost;
        }
        event.preventDefault();
        active.ghost.style.left = (event.clientX - active.offsetX) + 'px';
        active.ghost.style.top = (event.clientY - active.offsetY) + 'px';
        const target = targetAt(event.clientX, event.clientY);
        if (active.hover && active.hover !== target) active.hover.classList.remove('drop-hover');
        active.hover = null;
        if (target && target.classList.contains('dnd-zone') && compatible(active.item, target)) {
            target.classList.add('drop-hover');
            active.hover = target;
        }
        autoScroll(event.clientX, event.clientY);
    }, { passive: false });

    function endDrag(event, cancelled) {
        const active = drag.active;
        if (!active || event.pointerId !== active.pointerId) return;
        drag.active = null;
        if (active.hover) active.hover.classList.remove('drop-hover');
        if (active.ghost) active.ghost.remove();
        if (!active.started || cancelled) return;
        const part = partOf(active.item);
        const target = targetAt(event.clientX, event.clientY);
        if (!part) return;
        if (target && target.classList.contains('dnd-zone') && compatible(active.item, target)) {
            placeInZone(part, active.item, target);
        } else if (active.item.classList.contains('placed')) {
            clearZone(part, active.item.closest('.dnd-zone'));
        }
        drag.suppressClick = true;
        setTimeout(() => { drag.suppressClick = false; }, 50);
    }
    document.addEventListener('pointerup', (event) => endDrag(event, false));
    document.addEventListener('pointercancel', (event) => endDrag(event, true));

    document.addEventListener('click', (event) => {
        if (state.mode !== 'test' || drag.suppressClick) return;
        const target = event.target;
        if (!target.closest) return;
        const item = target.closest('.dnd-item');
        const zone = target.closest('.dnd-zone');
        const pool = target.closest('.dnd-pool');

        if (item && (!zone || !drag.tapSelected || drag.tapSelected === item)) {
            event.preventDefault();
            setTapSelected(drag.tapSelected === item ? null : item);
            return;
        }
        if (drag.tapSelected && zone && compatible(drag.tapSelected, zone)) {
            const part = partOf(zone);
            const selected = drag.tapSelected;
            setTapSelected(null);
            if (part) placeInZone(part, selected, zone);
            return;
        }
        if (drag.tapSelected && pool && drag.tapSelected.classList.contains('placed')) {
            const part = partOf(pool);
            const selected = drag.tapSelected;
            setTapSelected(null);
            if (part) clearZone(part, selected.closest('.dnd-zone'));
            return;
        }
        if (drag.tapSelected && !zone) setTapSelected(null);
    }, true);

    // ------------------------------------------------------------------
    // 作答状态
    // ------------------------------------------------------------------
    function multiValues(entry) {
        return entry.boxes.filter((box) => box.checked).map((box) => cleanText(box.value)).sort();
    }

    function answerOf(part, qid) {
        const control = part.controls.get(qid);
        if (!control) return '';
        switch (control.type) {
            case 'gap':
            case 'select':
                return cleanText(control.el.value);
            case 'radio': {
                const checked = control.els.find((radio) => radio.checked);
                return checked ? cleanText(checked.value) : '';
            }
            case 'zone': {
                const chip = placedChip(control.el);
                return chip ? chip.dataset.dndValue : '';
            }
            case 'multi': {
                const values = multiValues(control.group);
                const slot = control.group.qids.indexOf(qid);
                return values[slot] || '';
            }
            case 'essay':
                // 保留原文换行
                return control.el.value.trim() ? control.el.value : '';
            default:
                return '';
        }
    }

    function collectAnswers(part) {
        const answers = {};
        part.order.forEach((qid) => {
            const value = answerOf(part, qid);
            if (value) answers[qid] = value;
        });
        return answers;
    }

    function setAnswer(part, qid, value) {
        const control = part.controls.get(qid);
        if (!control || value == null || value === '') return;
        switch (control.type) {
            case 'gap':
            case 'select':
                control.el.value = value;
                break;
            case 'radio':
                control.els.forEach((radio) => { radio.checked = same(radio.value, value); });
                syncChoiceStyles(control.els[0]);
                break;
            case 'zone': {
                const groupIndex = control.el.dataset.dndGroup;
                const source = sourceItemFor(part, groupIndex, value);
                if (source) {
                    placeInZone(part, source, control.el, true);
                } else {
                    const chip = el('span', 'dnd-item placed', value);
                    chip.dataset.dndValue = value;
                    zoneHolder(control.el).appendChild(chip);
                    control.el.classList.add('filled');
                }
                break;
            }
            case 'multi':
                control.group.boxes.forEach((box) => {
                    if (same(box.value, value)) box.checked = true;
                });
                syncChoiceStyles(control.group.boxes[0]);
                break;
            case 'essay':
                control.el.value = value;
                updateWordCount(part);
                break;
        }
    }

    function syncChoiceStyles(input) {
        if (!input) return;
        const scope = input.closest('.question-block') || document;
        scope.querySelectorAll('input[name="' + input.name + '"]').forEach((node) => {
            const label = node.closest('label.choice-option');
            if (label) label.classList.toggle('selected', node.checked);
            const cell = node.closest('td');
            if (cell && !label) cell.classList.toggle('cell-selected', node.checked);
        });
    }

    function answerChanged(part, qid) {
        updateNavStatus(part);
        if (qid) setCurrent(part, qid, false);
        scheduleDraft();
    }

    document.addEventListener('input', (event) => {
        const target = event.target;
        if (!target.matches || !target.matches('input.gap, select.gap-select')) return;
        const part = partOf(target);
        if (part) answerChanged(part, target.dataset.q);
    });

    document.addEventListener('change', (event) => {
        const target = event.target;
        if (!target.matches) return;
        const part = partOf(target);
        if (!part) return;
        if (target.matches('input[type="radio"]')) {
            syncChoiceStyles(target);
            answerChanged(part, target.dataset.q);
        } else if (target.matches('input[type="checkbox"]')) {
            const entry = part.multiGroups.find((group) => group.boxes.includes(target));
            if (entry && target.checked && multiValues(entry).length > entry.qids.length) {
                target.checked = false;
                toast('Choose ' + entry.qids.length + ' answers only');
            }
            syncChoiceStyles(target);
            if (entry) answerChanged(part, entry.qids[0]);
        } else if (target.matches('select.gap-select')) {
            answerChanged(part, target.dataset.q);
        }
    });

    document.addEventListener('focusin', (event) => {
        const target = event.target;
        if (!target.dataset || !target.dataset.q) return;
        const part = partOf(target);
        if (part) setCurrent(part, target.dataset.q, false);
    });

    // ------------------------------------------------------------------
    // 底部导航
    // ------------------------------------------------------------------
    function renderNav() {
        navParts.innerHTML = '';
        state.parts.forEach((part) => {
            const section = el('div', 'nav-part');
            section.dataset.part = String(part.index);
            const label = el('div', 'nav-part-label');
            label.append(el('span', 'nav-part-name', 'Part ' + part.label), el('span', 'nav-part-count'));
            const list = el('div', 'nav-questions');
            if (part.writing) section.classList.add('writing');
            if (!part.writing) part.order.forEach((qid) => {
                const button = el('button', 'nav-q', numberOf(part, qid));
                button.type = 'button';
                button.dataset.q = qid;
                button.addEventListener('click', (event) => {
                    event.stopPropagation();
                    goTo(part, qid);
                });
                list.appendChild(button);
            });
            section.append(label, list);
            section.addEventListener('click', () => {
                if (state.currentPart !== part.index) switchPart(part.index, true);
            });
            navParts.appendChild(section);
            part.navSection = section;
            updateNavStatus(part);
        });
    }

    function updateNavStatus(part) {
        if (!part.navSection) return;
        if (part.writing) {
            part.navSection.classList.toggle('answered', !!answerOf(part, 'essay'));
            part.navSection.querySelector('.nav-part-count').textContent = '';
            return;
        }
        let answered = 0;
        part.navSection.querySelectorAll('.nav-q').forEach((button) => {
            const qid = button.dataset.q;
            const isAnswered = !!answerOf(part, qid);
            if (isAnswered) answered += 1;
            button.classList.toggle('answered', isAnswered);
            button.classList.toggle('review', state.reviews.has(part.index + ':' + qid));
            const result = state.results && state.results.parts[part.index] &&
                state.results.parts[part.index].questions[qid];
            button.classList.toggle('correct', !!(result && result.correct));
            button.classList.toggle('wrong', !!(result && !result.correct));
        });
        part.navSection.querySelector('.nav-part-count').textContent = answered + ' of ' + part.order.length;
        part.navSection.classList.toggle('has-review', part.order.some((qid) => state.reviews.has(part.index + ':' + qid)));
    }

    function switchPart(index, focusFirst) {
        state.currentPart = index;
        state.parts.forEach((part) => {
            part.view.classList.toggle('active', part.index === index);
            if (part.navSection) part.navSection.classList.toggle('active', part.index === index);
        });
        const part = state.parts[index];
        const first = numberOf(part, part.order[0]);
        const last = numberOf(part, part.order[part.order.length - 1]);
        $('part-title').textContent = 'Part ' + part.label;
        if (part.writing) {
            $('part-instruction').textContent = 'You should spend about ' + (part.label === 1 ? 20 : 40) +
                ' minutes on this task. Write at least ' + part.minWords + ' words.';
        } else {
            const verb = part.listening ? 'Listen and answer' : 'Read the text and answer';
            $('part-instruction').textContent = state.mode === 'study'
                ? 'Study mode: answers and explanations are shown for questions ' + first + '–' + last + '.'
                : verb + ' questions ' + first + '–' + last + '.';
        }
        // 考试模式下录音按顺序播放，查看其他 Part 的题目不会切换录音
        if (part.listening && !isStrictListening()) player.load(part);
        if (focusFirst && part.order.length) setCurrent(part, part.order[0], false);
        updateArrows();
        scheduleDraft();
    }

    function setCurrent(part, qid, scroll) {
        state.current = { part: part.index, qid };
        document.querySelectorAll('.nav-q.current').forEach((node) => node.classList.remove('current'));
        if (part.navSection) {
            const button = part.navSection.querySelector('.nav-q[data-q="' + qid + '"]');
            if (button) {
                button.classList.add('current');
                if (scroll) button.scrollIntoView({ block: 'nearest', inline: 'nearest' });
            }
        }
        syncReviewToggle();
        updateArrows();
    }

    // ------------------------------------------------------------------
    // Review：标记当前题目以便稍后检查（官方机考左下角的 Review，题号由方形变为圆形）
    // ------------------------------------------------------------------
    function syncReviewToggle() {
        const toggle = $('review-toggle');
        const part = state.current ? state.parts[state.current.part] : null;
        const available = state.mode === 'test' && !!part && !part.writing && !state.waitingStart;
        toggle.hidden = !available;
        const on = available && state.reviews.has(state.current.part + ':' + state.current.qid);
        toggle.classList.toggle('on', on);
        toggle.setAttribute('aria-pressed', on ? 'true' : 'false');
        toggle.setAttribute('aria-label', 'Review question ' + (part && state.current ? numberOf(part, state.current.qid) : ''));
    }

    function toggleReview() {
        if (!state.current || state.mode !== 'test') return;
        const part = state.parts[state.current.part];
        if (!part || part.writing) return;
        const key = part.index + ':' + state.current.qid;
        if (state.reviews.has(key)) state.reviews.delete(key);
        else state.reviews.add(key);
        updateNavStatus(part);
        syncReviewToggle();
        scheduleDraft();
    }

    $('review-toggle').addEventListener('click', toggleReview);

    function controlElement(part, qid) {
        const control = part.controls.get(qid);
        if (!control) return null;
        switch (control.type) {
            case 'gap':
            case 'select':
            case 'zone':
            case 'essay':
                return control.el;
            case 'radio':
                return control.els[0].closest('.question-item, .tfng-item, tr, .choice-item') || control.els[0].closest('label') || control.els[0];
            case 'multi':
                return control.group.boxes[0].closest('.question-item, .options') || control.group.boxes[0];
            default:
                return null;
        }
    }

    function goTo(part, qid) {
        if (state.currentPart !== part.index) switchPart(part.index, false);
        setCurrent(part, qid, true);
        const target = controlElement(part, qid);
        if (!target) return;
        target.scrollIntoView({ block: 'center', behavior: 'smooth' });
        target.classList.remove('question-flash');
        void target.offsetWidth;
        target.classList.add('question-flash');
        if (state.mode === 'test') focusControl(target);
    }

    /** 把键盘焦点放到题目的作答控件上（填空框、写作框，或单选/多选的第一个选项） */
    function focusControl(target) {
        if (!target) return;
        if (target.matches('input.gap, textarea.essay-input, select')) {
            target.focus({ preventScroll: true });
            return;
        }
        const option = target.querySelector('input[type="radio"]:checked, input[type="radio"], input[type="checkbox"]');
        if (option) option.focus({ preventScroll: true });
        else if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
    }

    function flatQuestions() {
        const list = [];
        state.parts.forEach((part) => part.order.forEach((qid) => list.push({ part, qid })));
        return list;
    }

    function step(delta) {
        const list = flatQuestions();
        if (!list.length) return;
        let index = state.current
            ? list.findIndex((item) => item.part.index === state.current.part && item.qid === state.current.qid)
            : -1;
        index = Math.min(Math.max(index + delta, 0), list.length - 1);
        goTo(list[index].part, list[index].qid);
    }

    function updateArrows() {
        const list = flatQuestions();
        const index = state.current
            ? list.findIndex((item) => item.part.index === state.current.part && item.qid === state.current.qid)
            : -1;
        $('prev-question').disabled = index <= 0;
        $('next-question').disabled = index >= list.length - 1;
    }

    $('prev-question').addEventListener('click', () => step(-1));
    $('next-question').addEventListener('click', () => step(1));

    // ------------------------------------------------------------------
    // 键盘（Magic Keyboard / 外接键盘）
    // - Tab / Shift+Tab：下一题 / 上一题（与官方机考一致）
    // - 在填空框、写作框中：方向键移动光标（系统默认行为）
    // - 在单选 / 多选选项上：↑↓ 切换选项，空格勾选多选
    // - 其他位置：← → 上一题 / 下一题，↑ ↓ 滚动题目
    // - Esc：关闭菜单、笔记与对话框
    // ------------------------------------------------------------------
    function overlayOpen() {
        return !$('context-menu').hidden || $('note-editor').classList.contains('show') ||
            $('dialog').classList.contains('show') || $('options-menu').classList.contains('show');
    }

    function scrollPane(delta) {
        const part = state.parts[state.currentPart];
        if (!part) return;
        const pane = lastPointerPane && part.view.contains(lastPointerPane) ? lastPointerPane : part.questions;
        pane.scrollBy({ top: delta, behavior: 'smooth' });
    }

    function moveOption(input, delta) {
        const scope = input.closest('.question-block') || document;
        const options = Array.from(scope.querySelectorAll('input[name="' + input.name + '"]')).filter((node) => !node.disabled);
        const index = options.indexOf(input);
        const next = options[Math.min(Math.max(index + delta, 0), options.length - 1)];
        if (!next || next === input) return;
        next.focus({ preventScroll: false });
        if (next.type === 'radio') {
            next.checked = true;
            next.dispatchEvent(new Event('change', { bubbles: true }));
        }
    }

    /** 处理按键，返回是否已处理。原生端在网页没有焦点时也会转发 Tab 与方向键。 */
    function handleKey(key, shift, target) {
        if (key === 'Escape') {
            if (!$('context-menu').hidden) { hideContextMenu(); return true; }
            if ($('note-editor').classList.contains('show')) { closeNoteEditor(true); return true; }
            if ($('dialog').classList.contains('show')) { closeDialog(false); return true; }
            if ($('options-menu').classList.contains('show')) { toggleMenu(false); return true; }
            return false;
        }
        if (overlayOpen() || state.waitingStart || !state.parts.length) return false;
        if (key === 'Tab') {
            step(shift ? -1 : 1);
            return true;
        }
        if (isTextField(target) || (target && target.matches && target.matches('select'))) return false;
        const option = target && target.matches && target.matches('input[type="radio"], input[type="checkbox"]') ? target : null;
        switch (key) {
            case 'ArrowUp':
            case 'ArrowDown':
                if (option) moveOption(option, key === 'ArrowUp' ? -1 : 1);
                else scrollPane(key === 'ArrowUp' ? -80 : 80);
                return true;
            case 'ArrowLeft':
            case 'ArrowRight':
                if (option) moveOption(option, key === 'ArrowLeft' ? -1 : 1);
                else step(key === 'ArrowLeft' ? -1 : 1);
                return true;
            case 'PageUp':
            case 'PageDown':
                scrollPane((key === 'PageUp' ? -1 : 1) * window.innerHeight * 0.6);
                return true;
            default:
                return false;
        }
    }

    let lastPointerPane = null;
    document.addEventListener('pointerdown', (event) => {
        lastPointerPane = event.target.closest ? event.target.closest('.pane') : null;
    }, true);

    document.addEventListener('keydown', (event) => {
        if (event.metaKey || event.ctrlKey || event.altKey) return;
        if (handleKey(event.key, event.shiftKey, event.target)) event.preventDefault();
    }, true);

    // 告诉原生端当前是否在输入框中：输入时方向键交给系统移动光标，其余时候由原生端转发给引擎
    function reportEditing() {
        post('editing', { editing: isTextField(document.activeElement) });
    }
    document.addEventListener('focusin', reportEditing);
    document.addEventListener('focusout', () => setTimeout(reportEditing, 0));

    // ------------------------------------------------------------------
    // 分栏拖动
    // ------------------------------------------------------------------
    function setUpDivider(divider, view) {
        divider.addEventListener('pointerdown', (event) => {
            event.preventDefault();
            divider.setPointerCapture(event.pointerId);
            divider.classList.add('dragging');
            const vertical = window.matchMedia('(max-width: 760px)').matches;
            const move = (moveEvent) => {
                const rect = view.getBoundingClientRect();
                const ratio = vertical
                    ? (moveEvent.clientY - rect.top) / rect.height
                    : (moveEvent.clientX - rect.left) / rect.width;
                applySplit(Math.min(Math.max(ratio, 0.22), 0.78));
            };
            const up = () => {
                divider.classList.remove('dragging');
                divider.removeEventListener('pointermove', move);
                divider.removeEventListener('pointerup', up);
                divider.removeEventListener('pointercancel', up);
                post('preferences', state.preferences);
            };
            divider.addEventListener('pointermove', move);
            divider.addEventListener('pointerup', up);
            divider.addEventListener('pointercancel', up);
        });
        divider.addEventListener('dblclick', () => {
            applySplit(0.5);
            post('preferences', state.preferences);
        });
    }

    function applySplit(ratio) {
        state.preferences.split = ratio;
        document.documentElement.style.setProperty('--split', (ratio * 100).toFixed(2) + '%');
    }

    // ------------------------------------------------------------------
    // 计时
    // ------------------------------------------------------------------
    function startTimer() {
        const timer = state.timer;
        timer.last = performance.now();
        clearInterval(timer.handle);
        timer.handle = setInterval(tick, 250);
        renderTimer();
    }

    function tick() {
        const timer = state.timer;
        const now = performance.now();
        const delta = Math.min((now - timer.last) / 1000, 2);
        timer.last = now;
        if (state.mode !== 'test' || timer.paused || state.waitingStart || state.submitted) return;
        timer.elapsed += delta;
        if (state.listeningReview.started) {
            state.listeningReview.elapsed += delta;
            if (state.listeningReview.elapsed >= REVIEW_SECONDS) {
                renderTimer();
                toast('Time is up');
                submit(true);
                return;
            }
        }
        renderTimer();
        if (timer.kind === 'countdown' && timer.elapsed >= timer.limit && !state.submitted) {
            toast('Time is up');
            submit(true);
        }
    }

    function formatClock(seconds) {
        const total = Math.max(0, Math.floor(seconds));
        const h = Math.floor(total / 3600);
        const m = Math.floor((total % 3600) / 60);
        const s = total % 60;
        const mm = String(m).padStart(h ? 2 : 1, '0');
        return (h ? h + ':' : '') + mm + ':' + String(s).padStart(2, '0');
    }

    function listeningRemaining() {
        if (state.listeningReview.started) return Math.max(REVIEW_SECONDS - state.listeningReview.elapsed, 0);
        let total = REVIEW_SECONDS;
        const current = player.part ? player.part.index : 0;
        for (let i = current; i < state.parts.length; i += 1) {
            const duration = state.parts[i].duration;
            if (!duration) return null;
            total += i === current ? Math.max(duration - (audio.currentTime || 0), 0) : duration;
        }
        return total;
    }

    function renderRemaining(remaining) {
        if (remaining > 60) {
            const minutes = Math.ceil(remaining / 60);
            timerText.textContent = minutes + (minutes === 1 ? ' minute left' : ' minutes left');
        } else {
            const seconds = Math.ceil(remaining);
            timerText.textContent = seconds + (seconds === 1 ? ' second left' : ' seconds left');
        }
        if (remaining <= 60) timerButton.classList.add('critical');
        else if (remaining <= 600) timerButton.classList.add('warn');
    }

    function renderTimer() {
        const timer = state.timer;
        timerButton.classList.toggle('paused', timer.paused && !state.waitingStart && state.mode === 'test');
        timerButton.classList.toggle('hidden-time', state.preferences.hideTimer && state.mode === 'test');
        timerButton.classList.remove('warn', 'critical');
        if (state.mode !== 'test') {
            timerText.textContent = state.mode === 'study' ? 'Study mode' : 'Time taken ' + formatClock(timer.elapsed);
            return;
        }
        if (isStrictListening()) {
            const remaining = listeningRemaining();
            if (remaining == null) timerText.textContent = 'Listening';
            else renderRemaining(remaining);
        } else if (timer.kind === 'countdown') {
            renderRemaining(Math.max(timer.limit - timer.elapsed, 0));
        } else if (timer.kind === 'countup') {
            timerText.textContent = formatClock(timer.elapsed) + ' elapsed';
        } else {
            timerText.textContent = 'Untimed';
        }
    }

    timerButton.addEventListener('click', () => {
        if (state.mode !== 'test' || state.timer.kind === 'none' || isStrict() || state.waitingStart) return;
        state.timer.paused = !state.timer.paused;
        renderTimer();
        toast(state.timer.paused ? 'Timer paused' : 'Timer resumed');
        scheduleDraft();
    });

    // ------------------------------------------------------------------
    // 划线 / 笔记
    // ------------------------------------------------------------------
    const SKIP_SELECTOR = '.dnd-zone, .dnd-pool, .answer-chip, .explanations, .passage-note, .result-card, .questions-header, input, select, textarea, .qnum-inline-hidden';

    function textWalker(pane) {
        return document.createTreeWalker(pane, NodeFilter.SHOW_TEXT, {
            acceptNode(node) {
                const parent = node.parentElement;
                if (!parent || parent.closest(SKIP_SELECTOR)) return NodeFilter.FILTER_REJECT;
                return NodeFilter.FILTER_ACCEPT;
            },
        });
    }

    function selectionPane(range) {
        const node = range.commonAncestorContainer;
        const element = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement;
        return element ? element.closest('.pane') : null;
    }

    function wrapRange(pane, range, id, note) {
        const walker = textWalker(pane);
        const targets = [];
        let node;
        while ((node = walker.nextNode())) {
            if (!range.intersectsNode(node)) continue;
            let start = 0;
            let end = node.textContent.length;
            if (node === range.startContainer) start = range.startOffset;
            if (node === range.endContainer) end = range.endOffset;
            if (end > start) targets.push({ node, start, end });
        }
        const marks = [];
        targets.forEach(({ node: textNode, start, end }) => {
            let target = textNode;
            if (start > 0) target = target.splitText(start);
            if (end - start < target.textContent.length) target.splitText(end - start);
            if (!target.textContent.trim() && marks.length === 0) return;
            const mark = el('mark', 'hl');
            mark.dataset.hl = id;
            target.parentNode.insertBefore(mark, target);
            mark.appendChild(target);
            marks.push(mark);
        });
        if (marks.length && note) applyNote(id, note);
        return marks;
    }

    function applyNote(id, note) {
        const marks = document.querySelectorAll('mark.hl[data-hl="' + id + '"]');
        marks.forEach((mark, index) => {
            mark.classList.toggle('has-note', !!note);
            mark.dataset.note = note || '';
            if (index === 0 && note) mark.setAttribute('data-note-start', '');
            else mark.removeAttribute('data-note-start');
        });
    }

    function removeHighlight(id) {
        document.querySelectorAll('mark.hl[data-hl="' + id + '"]').forEach((mark) => {
            const parent = mark.parentNode;
            while (mark.firstChild) parent.insertBefore(mark.firstChild, mark);
            mark.remove();
            parent.normalize();
        });
        scheduleDraft();
    }

    function highlightSelection(kind) {
        const selection = window.getSelection();
        if (!selection || selection.rangeCount === 0 || selection.isCollapsed) return false;
        const range = selection.getRangeAt(0);
        const pane = selectionPane(range);
        if (!pane) return false;

        if (kind === 'clear') {
            const ids = new Set();
            pane.querySelectorAll('mark.hl').forEach((mark) => {
                if (range.intersectsNode(mark)) ids.add(mark.dataset.hl);
            });
            ids.forEach(removeHighlight);
            selection.removeAllRanges();
            return ids.size > 0;
        }

        const id = 'h' + (++state.highlightSeq);
        const marks = wrapRange(pane, range, id, '');
        selection.removeAllRanges();
        if (!marks.length) return false;
        scheduleDraft();
        if (kind === 'note') openNoteEditor(id);
        return true;
    }

    function serializeHighlights() {
        const list = [];
        state.parts.forEach((part) => {
            [part.passage, part.questions].forEach((pane) => {
                const walker = textWalker(pane);
                const spans = new Map();
                let offset = 0;
                let node;
                while ((node = walker.nextNode())) {
                    const length = node.textContent.length;
                    const mark = node.parentElement.closest('mark.hl');
                    if (mark) {
                        const id = mark.dataset.hl;
                        const span = spans.get(id) || { start: offset, end: offset, note: mark.dataset.note || '' };
                        span.end = offset + length;
                        spans.set(id, span);
                    }
                    offset += length;
                }
                spans.forEach((span) => list.push({
                    part: part.index,
                    pane: pane.dataset.pane,
                    start: span.start,
                    end: span.end,
                    note: span.note,
                }));
            });
        });
        return list;
    }

    function restoreHighlights(list) {
        (list || []).forEach((item) => {
            const part = state.parts[item.part];
            if (!part) return;
            const pane = item.pane === 'questions' ? part.questions : part.passage;
            const walker = textWalker(pane);
            const range = document.createRange();
            let offset = 0;
            let startSet = false;
            let node;
            while ((node = walker.nextNode())) {
                const length = node.textContent.length;
                if (!startSet && item.start < offset + length) {
                    range.setStart(node, Math.max(item.start - offset, 0));
                    startSet = true;
                }
                if (startSet && item.end <= offset + length) {
                    range.setEnd(node, Math.max(item.end - offset, 0));
                    const id = 'h' + (++state.highlightSeq);
                    wrapRange(pane, range, id, item.note || '');
                    return;
                }
                offset += length;
            }
        });
    }

    let editingHighlight = null;

    function openNoteEditor(id) {
        const marks = document.querySelectorAll('mark.hl[data-hl="' + id + '"]');
        if (!marks.length) return;
        editingHighlight = id;
        const editor = $('note-editor');
        const quote = Array.from(marks).map((mark) => mark.textContent).join('');
        $('note-quote').textContent = '“' + cleanText(quote).slice(0, 140) + '”';
        $('note-text').value = marks[0].dataset.note || '';
        const rect = marks[0].getBoundingClientRect();
        editor.classList.add('show');
        const width = editor.offsetWidth;
        const height = editor.offsetHeight;
        let left = Math.min(Math.max(rect.left, 12), window.innerWidth - width - 12);
        let top = rect.bottom + 10;
        if (top + height > window.innerHeight - 80) top = Math.max(rect.top - height - 10, 70);
        editor.style.left = left + 'px';
        editor.style.top = top + 'px';
        $('scrim').classList.add('show');
        $('scrim').dataset.owner = 'note';
    }

    function closeNoteEditor(save) {
        if (editingHighlight && save) {
            applyNote(editingHighlight, $('note-text').value.trim());
            scheduleDraft();
        }
        editingHighlight = null;
        $('note-editor').classList.remove('show');
        $('scrim').classList.remove('show');
        $('note-text').blur();
    }

    $('note-save').addEventListener('click', () => closeNoteEditor(true));
    $('note-close').addEventListener('click', () => closeNoteEditor(true));
    $('note-delete').addEventListener('click', () => {
        const id = editingHighlight;
        closeNoteEditor(false);
        if (id) removeHighlight(id);
    });

    // 点按带笔记的高亮可查看、修改笔记；普通高亮点按无反应（与官方一致，清除请右键 Clear）
    document.addEventListener('click', (event) => {
        const mark = event.target.closest && event.target.closest('mark.hl.has-note');
        if (!mark) return;
        const selection = window.getSelection();
        if (selection && !selection.isCollapsed) return;
        openNoteEditor(mark.dataset.hl);
    });

    // ------------------------------------------------------------------
    // 右键菜单：选中文字后右键（触控板双指点按）→ Highlight / Notes；在高亮上右键 → Notes / Clear
    // ------------------------------------------------------------------
    const contextMenu = $('context-menu');
    let menuState = null;

    function marksInRange(pane, range) {
        const ids = new Set();
        pane.querySelectorAll('mark.hl').forEach((mark) => {
            if (range.intersectsNode(mark)) ids.add(mark.dataset.hl);
        });
        return ids;
    }

    function hideContextMenu() {
        contextMenu.hidden = true;
        menuState = null;
    }

    function showContextMenu(event) {
        const target = event.target;
        const pane = target.closest && target.closest('.pane');
        if (!pane || target.closest('input, textarea, select')) return false;
        const selection = window.getSelection();
        let range = null;
        if (selection && selection.rangeCount && !selection.isCollapsed) {
            const candidate = selection.getRangeAt(0);
            if (selectionPane(candidate) === pane) range = candidate.cloneRange();
        }
        const mark = target.closest('mark.hl');
        const ids = range ? marksInRange(pane, range) : new Set(mark ? [mark.dataset.hl] : []);
        const part = state.parts[state.currentPart];
        const anyMarks = !!part && !!part.view.querySelector('mark.hl');
        const text = range ? cleanText(range.toString()) : '';
        const words = text.split(' ').filter(Boolean);
        const wordLike = words.length > 0 && words.length <= 3 && /^[A-Za-z][A-Za-z' -]*$/.test(text);
        const visible = {
            highlight: !!range,
            note: !!range || !!mark,
            clear: ids.size > 0,
            'clear-all': anyMarks,
            vocab: wordLike,
        };
        if (!Object.values(visible).some(Boolean)) return false;
        contextMenu.querySelectorAll('[data-action]').forEach((item) => { item.hidden = !visible[item.dataset.action]; });
        contextMenu.querySelector('hr').hidden = !visible.vocab;
        menuState = { range, mark, ids };
        contextMenu.hidden = false;
        const width = contextMenu.offsetWidth;
        const height = contextMenu.offsetHeight;
        contextMenu.style.left = Math.min(event.clientX, window.innerWidth - width - 8) + 'px';
        contextMenu.style.top = Math.min(event.clientY, window.innerHeight - height - 8) + 'px';
        return true;
    }

    document.addEventListener('contextmenu', (event) => {
        if (state.waitingStart) return;
        if (showContextMenu(event)) event.preventDefault();
    });

    contextMenu.addEventListener('pointerdown', (event) => event.preventDefault());
    contextMenu.addEventListener('click', (event) => {
        const item = event.target.closest('[data-action]');
        if (!item || !menuState) return;
        const { range, mark, ids } = menuState;
        hideContextMenu();
        const selection = window.getSelection();
        const restore = () => {
            if (!range) return;
            selection.removeAllRanges();
            selection.addRange(range);
        };
        switch (item.dataset.action) {
            case 'highlight':
                restore();
                highlightSelection('highlight');
                break;
            case 'note':
                if (range) {
                    restore();
                    highlightSelection('note');
                } else if (mark) {
                    openNoteEditor(mark.dataset.hl);
                }
                break;
            case 'clear':
                ids.forEach(removeHighlight);
                selection.removeAllRanges();
                break;
            case 'clear-all': {
                const part = state.parts[state.currentPart];
                if (part) new Set(Array.from(part.view.querySelectorAll('mark.hl')).map((node) => node.dataset.hl)).forEach(removeHighlight);
                selection.removeAllRanges();
                break;
            }
            case 'vocab':
                restore();
                post('vocab', selectionInfo());
                selection.removeAllRanges();
                break;
        }
    });

    document.addEventListener('pointerdown', (event) => {
        if (!contextMenu.hidden && !contextMenu.contains(event.target)) hideContextMenu();
    }, true);
    document.addEventListener('scroll', () => { if (!contextMenu.hidden) hideContextMenu(); }, true);

    function selectionInfo() {
        const selection = window.getSelection();
        if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
            return { hasSelection: false, inHighlight: false, text: '', sentence: '' };
        }
        const range = selection.getRangeAt(0);
        const pane = selectionPane(range);
        let inHighlight = false;
        if (pane) {
            pane.querySelectorAll('mark.hl').forEach((mark) => {
                if (range.intersectsNode(mark)) inHighlight = true;
            });
        }
        const text = cleanText(selection.toString());
        const block = range.startContainer.parentElement && range.startContainer.parentElement.closest('p, li, td, div');
        let sentence = '';
        if (block) {
            const full = cleanText(block.textContent);
            const at = full.indexOf(text);
            if (at >= 0) {
                const before = full.lastIndexOf('. ', at);
                const after = full.indexOf('. ', at + text.length);
                sentence = full.slice(before >= 0 ? before + 2 : 0, after >= 0 ? after + 1 : full.length).trim();
            }
        }
        return { hasSelection: !!pane && !!text, inHighlight, text: text.slice(0, 120), sentence: sentence.slice(0, 400) };
    }

    let selectionTimer = 0;
    document.addEventListener('selectionchange', () => {
        clearTimeout(selectionTimer);
        selectionTimer = setTimeout(() => post('selection', selectionInfo()), 0);
    });

    // ------------------------------------------------------------------
    // 菜单 / 对话框
    // ------------------------------------------------------------------
    function applyPreferences() {
        const prefs = state.preferences;
        document.body.classList.remove('contrast-inverse', 'contrast-yellow');
        if (prefs.contrast === 'inverse') document.body.classList.add('contrast-inverse');
        if (prefs.contrast === 'yellow') document.body.classList.add('contrast-yellow');
        document.documentElement.classList.remove('text-large', 'text-xlarge');
        if (prefs.textSize === 'large') document.documentElement.classList.add('text-large');
        if (prefs.textSize === 'xlarge') document.documentElement.classList.add('text-xlarge');
        applySplit(prefs.split || 0.5);
        document.querySelectorAll('[data-contrast]').forEach((row) => row.classList.toggle('selected', row.dataset.contrast === prefs.contrast));
        document.querySelectorAll('[data-text-size]').forEach((row) => row.classList.toggle('selected', row.dataset.textSize === prefs.textSize));
        $('toggle-timer-visibility').classList.toggle('selected', !!prefs.hideTimer);
        renderTimer();
    }

    function toggleMenu(show) {
        const menu = $('options-menu');
        const visible = show === undefined ? !menu.classList.contains('show') : show;
        menu.classList.toggle('show', visible);
        $('scrim').classList.toggle('show', visible);
        $('scrim').dataset.owner = visible ? 'menu' : '';
    }

    $('menu-button').addEventListener('click', () => toggleMenu());
    $('scrim').addEventListener('click', () => {
        if ($('scrim').dataset.owner === 'note') closeNoteEditor(true);
        else if ($('scrim').dataset.owner === 'dialog') closeDialog(false);
        else toggleMenu(false);
    });
    document.querySelectorAll('[data-contrast]').forEach((row) => row.addEventListener('click', () => {
        state.preferences.contrast = row.dataset.contrast;
        applyPreferences();
        post('preferences', state.preferences);
    }));
    document.querySelectorAll('[data-text-size]').forEach((row) => row.addEventListener('click', () => {
        state.preferences.textSize = row.dataset.textSize;
        applyPreferences();
        post('preferences', state.preferences);
    }));
    $('toggle-timer-visibility').addEventListener('click', () => {
        state.preferences.hideTimer = !state.preferences.hideTimer;
        applyPreferences();
        post('preferences', state.preferences);
    });
    $('exit-button').addEventListener('click', () => {
        toggleMenu(false);
        requestExit();
    });

    let dialogHandler = null;
    function openDialog(title, message, confirmLabel, cancelLabel, handler) {
        $('dialog-title').textContent = title;
        $('dialog-message').textContent = message;
        $('dialog-confirm').textContent = confirmLabel;
        $('dialog-cancel').textContent = cancelLabel;
        $('dialog-cancel').style.display = cancelLabel ? '' : 'none';
        dialogHandler = handler;
        $('dialog').classList.add('show');
        $('scrim').classList.add('show');
        $('scrim').dataset.owner = 'dialog';
    }
    function closeDialog(confirmed) {
        $('dialog').classList.remove('show');
        $('scrim').classList.remove('show');
        const handler = dialogHandler;
        dialogHandler = null;
        if (handler) handler(confirmed);
    }
    $('dialog-confirm').addEventListener('click', () => closeDialog(true));
    $('dialog-cancel').addEventListener('click', () => closeDialog(false));

    function requestExit() {
        if (state.mode !== 'test' || state.waitingStart || state.submitted) {
            post('exit', { inProgress: false });
            return;
        }
        openDialog('Leave the test?', 'Your answers, highlights and time will be saved. You can continue later from where you left off.',
            'Leave', 'Stay', (confirmed) => {
                if (!confirmed) return;
                flushDraft();
                post('exit', { inProgress: true });
            });
    }

    // ------------------------------------------------------------------
    // 草稿 / 提交
    // ------------------------------------------------------------------
    function draftPayload() {
        return {
            parts: state.parts.map((part) => ({ examId: part.exam.id, answers: collectAnswers(part) })),
            highlights: serializeHighlights(),
            elapsed: Math.round(state.timer.elapsed),
            paused: state.timer.paused,
            currentPart: state.currentPart,
            audioPart: player.part ? player.part.index : 0,
            audioTime: player.part ? Math.floor(audio.currentTime || 0) : 0,
            reviewElapsed: state.listeningReview.started ? Math.round(state.listeningReview.elapsed) : null,
            reviews: Array.from(state.reviews),
        };
    }

    function scheduleDraft() {
        if (state.mode !== 'test' || state.submitted || state.waitingStart) return;
        clearTimeout(state.draftTimer);
        state.draftTimer = setTimeout(flushDraft, 700);
    }

    function flushDraft() {
        if (state.mode !== 'test' || state.submitted) return;
        clearTimeout(state.draftTimer);
        post('draft', draftPayload());
    }

    setInterval(() => {
        if (state.mode === 'test' && !state.submitted && !state.timer.paused && !state.waitingStart) flushDraft();
    }, 15000);

    document.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'hidden') flushDraft();
    });

    function unansweredCount() {
        return state.parts.reduce((sum, part) => sum + part.order.filter((qid) => !answerOf(part, qid)).length, 0);
    }

    function submit(force) {
        if (state.mode !== 'test' || state.submitted) {
            if (state.mode !== 'test') post('exit', { inProgress: false });
            return;
        }
        const send = () => {
            state.submitted = true;
            state.timer.paused = true;
            clearTimeout(state.draftTimer);
            const payload = draftPayload();
            payload.timeUp = !!force;
            post('submit', payload);
        };
        if (force) {
            send();
            return;
        }
        const missing = unansweredCount();
        const unit = state.parts.some((part) => part.writing) ? 'part' : 'question';
        const prefix = missing
            ? 'You have ' + missing + ' unanswered ' + unit + (missing === 1 ? '' : 's') + '. '
            : '';
        openDialog('Submit your answers?', prefix + 'You will not be able to change your answers after submitting.',
            'Submit', 'Cancel', (confirmed) => { if (confirmed) send(); });
    }

    $('submit-button').addEventListener('click', () => submit(false));

    // ------------------------------------------------------------------
    // 复盘 / 背题
    // ------------------------------------------------------------------
    function expectedLabel(part, qid, expected) {
        const zone = part.zones.get(qid);
        if (zone) {
            const item = sourceItemFor(part, zone.dataset.dndGroup, expected[0]);
            if (item) return shortLabel(item);
        }
        return expected.join(' / ');
    }

    function chip(text, wrong) {
        const node = el('span', 'answer-chip' + (wrong ? ' wrong' : ''), text);
        return node;
    }

    function decorate(part, results) {
        part.order.forEach((qid) => {
            const result = results.questions[qid];
            const control = part.controls.get(qid);
            if (!result || !control) return;
            const ok = !!result.correct;
            const expected = result.expected || [];
            switch (control.type) {
                case 'gap':
                case 'select': {
                    control.el.classList.add(ok ? 'is-correct' : 'is-wrong');
                    control.el.readOnly = true;
                    if (control.type === 'select') control.el.disabled = true;
                    if (!ok && expected.length) control.el.insertAdjacentElement('afterend', chip('✓ ' + expected.join(' / ')));
                    break;
                }
                case 'radio':
                    control.els.forEach((radio) => {
                        radio.disabled = true;
                        const holder = radio.closest('label.choice-option') || radio.closest('td');
                        if (!holder) return;
                        if (includesValue(expected, radio.value)) holder.classList.add('is-answer');
                        else if (radio.checked) holder.classList.add('is-wrong');
                    });
                    break;
                case 'zone': {
                    control.el.classList.add(ok ? 'is-correct' : 'is-wrong');
                    if (!ok && expected.length) control.el.insertAdjacentElement('afterend', chip('✓ ' + expectedLabel(part, qid, expected)));
                    break;
                }
                case 'essay':
                    control.el.readOnly = true;
                    break;
                case 'multi': {
                    const entry = control.group;
                    if (entry.decorated) break;
                    entry.decorated = true;
                    const all = new Set();
                    entry.qids.forEach((id) => (results.questions[id] && results.questions[id].expected || []).forEach((value) => all.add(cleanText(value).toLowerCase())));
                    entry.boxes.forEach((box) => {
                        box.disabled = true;
                        const holder = box.closest('label.choice-option');
                        if (!holder) return;
                        if (all.has(cleanText(box.value).toLowerCase())) holder.classList.add('is-answer');
                        else if (box.checked) holder.classList.add('is-wrong');
                    });
                    break;
                }
            }
        });
        part.view.querySelectorAll('.dnd-item').forEach((item) => item.classList.remove('tap-selected'));
        updateNavStatus(part);
    }

    function renderExplanations(part, results, showYours) {
        const notes = (part.explanation && part.explanation.questionNotes) || {};
        part.questions.querySelectorAll('.question-block').forEach((wrap) => {
            const group = part.exam.questionGroups[Number(wrap.dataset.group)];
            if (!group) return;
            const box = el('div', 'explanations' + (showYours ? '' : ' study'));
            box.appendChild(el('header', null, 'Answers & explanations 答案与解析'));
            group.questionIds.forEach((qid) => {
                const result = results.questions[qid] || {};
                const row = el('details', 'explanation-row');
                const summary = el('summary');
                summary.appendChild(el('span', 'num', numberOf(part, qid)));
                const yours = el('span', 'yours' + (showYours && !result.correct ? ' wrong' : ''),
                    showYours ? (result.given || '—') : '');
                summary.appendChild(yours);
                summary.appendChild(el('span', 'key', expectedLabel(part, qid, result.expected || [])));
                summary.appendChild(el('span', 'mark ' + (result.correct ? 'ok' : 'bad'), showYours ? (result.correct ? '✓' : '✗') : '›'));
                row.appendChild(summary);
                const text = notes[qid];
                row.appendChild(el('div', 'body' + (text ? '' : ' empty'), text || '暂无解析'));
                box.appendChild(row);
            });
            wrap.appendChild(box);
        });
    }

    function renderPassageNotes(part) {
        const notes = (part.explanation && part.explanation.passageNotes) || [];
        if (!notes.length) return;
        const paragraphs = Array.from(part.passage.querySelectorAll('p')).filter((p) => {
            const text = cleanText(p.textContent);
            return text.length >= 60 && !/^You should spend about/i.test(text) && !p.closest('.dnd-zone');
        });
        const byLetter = new Map();
        paragraphs.forEach((p) => {
            const first = p.querySelector('strong, b');
            const letter = first && /^[A-Z]$/.test(cleanText(first.textContent)) ? cleanText(first.textContent) : null;
            if (letter && cleanText(p.textContent).startsWith(letter)) byLetter.set(letter, p);
        });
        const leftovers = [];
        const indexed = !!part.passage.querySelector('p[data-para]');
        notes.forEach((note, index) => {
            const match = /Paragraph\s+([A-Z])\b/i.exec(note.label || '');
            let anchor = indexed && note.index != null
                ? part.passage.querySelector('p[data-para="' + note.index + '"]')
                : null;
            if (!anchor && match) anchor = byLetter.get(match[1].toUpperCase());
            if (!anchor && paragraphs.length === notes.length) anchor = paragraphs[index];
            const block = el('div', 'passage-note');
            block.appendChild(el('span', 'label', note.label || ('Paragraph ' + (index + 1))));
            block.appendChild(document.createTextNode(note.text || ''));
            if (anchor) anchor.insertAdjacentElement('afterend', block);
            else leftovers.push(block);
        });
        if (leftovers.length) {
            const container = el('div', 'passage-notes-tail');
            leftovers.forEach((block) => container.appendChild(block));
            part.passage.appendChild(container);
        }
    }

    function renderResultCard(part, results) {
        const card = el('div', 'result-card' + (state.mode === 'study' ? ' study' : ''));
        if (part.writing) {
            const words = countWords(part.textarea.value);
            const score = el('div', 'score', words + (words === 1 ? ' word' : ' words'));
            score.appendChild(el('small', null, words >= part.minWords
                ? '达到 ' + part.minWords + ' 词要求' : '少于 ' + part.minWords + ' 词要求'));
            card.appendChild(score);
            const meta = el('div', 'meta');
            meta.appendChild(el('span', null, 'Task ' + part.label));
            if (part.index === 0 && state.results) {
                meta.appendChild(el('span', null, 'Time ' + formatClock(state.results.elapsed || state.timer.elapsed)));
            }
            if (!part.exam.essay) meta.appendChild(el('span', null, '本题没有参考范文'));
            card.appendChild(meta);
        } else if (state.mode === 'study') {
            card.appendChild(el('div', 'score', '背题模式 · Study mode'));
            const meta = el('div', 'meta');
            meta.appendChild(el('span', null, 'Correct answers are filled in. 展开下方条目查看解析。'));
            card.appendChild(meta);
        } else {
            const partResult = results;
            const score = el('div', 'score', partResult.score + ' / ' + partResult.total);
            const percent = partResult.total ? Math.round((partResult.score / partResult.total) * 100) : 0;
            score.appendChild(el('small', null, percent + '%'));
            card.appendChild(score);
            const meta = el('div', 'meta');
            if (part.index === 0 && state.results) {
                meta.appendChild(el('span', null, 'Time ' + formatClock(state.results.elapsed || state.timer.elapsed)));
                if (state.results.band) meta.appendChild(el('span', null, 'Estimated band ' + state.results.band));
                if (state.parts.length > 1) meta.appendChild(el('span', null, 'Total ' + state.results.score + ' / ' + state.results.total));
            }
            card.appendChild(meta);
        }
        const actions = el('div', 'actions');
        if (part.writing && part.exam.essay) {
            const toggle = el('button', 'model-toggle', '参考范文');
            toggle.type = 'button';
            toggle.addEventListener('click', () => {
                const block = part.passage.querySelector('.model-answer');
                if (block) block.scrollIntoView({ block: 'start', behavior: 'smooth' });
            });
            actions.appendChild(toggle);
        }
        const hasNotes = state.parts.some((p) => p.explanation && (p.explanation.passageNotes || []).length);
        const hasTranscriptZh = state.parts.some((p) => p.listening && p.transcript.some((line) => line.zh));
        if (hasNotes || hasTranscriptZh) {
            const toggle = el('button', 'translation-toggle', hasTranscriptZh ? '中文对照' : '段落翻译');
            toggle.type = 'button';
            toggle.addEventListener('click', () => {
                const on = document.body.classList.toggle('show-translation');
                document.querySelectorAll('.translation-toggle').forEach((button) => button.classList.toggle('on', on));
            });
            actions.appendChild(toggle);
        }
        if (!part.writing) {
            const expand = el('button', null, '展开全部解析');
            expand.type = 'button';
            expand.addEventListener('click', () => {
                const rows = part.questions.querySelectorAll('.explanation-row');
                const open = Array.from(rows).some((row) => !row.open);
                rows.forEach((row) => { row.open = open; });
                expand.textContent = open ? '收起全部解析' : '展开全部解析';
            });
            actions.appendChild(expand);
        }
        const extra = state.config.actions || {};
        if (extra.retry) {
            const retry = el('button', null, '重新练习');
            retry.type = 'button';
            retry.addEventListener('click', () => post('retry'));
            actions.appendChild(retry);
        }
        if (extra.next && !part.writing) {
            const next = el('button', null, '下一篇');
            next.type = 'button';
            next.addEventListener('click', () => post('next'));
            actions.appendChild(next);
        }
        card.appendChild(actions);
        part.header.innerHTML = '';
        part.header.appendChild(card);
    }

    function enterReview(results, answersByPart) {
        state.results = results;
        state.timer.paused = true;
        if (answersByPart) {
            state.parts.forEach((part, index) => {
                const answers = (answersByPart[index] && answersByPart[index].answers) || {};
                Object.keys(answers).forEach((qid) => setAnswer(part, qid, answers[qid]));
            });
        }
        document.body.classList.add('reviewing');
        state.parts.forEach((part, index) => {
            const partResults = results.parts[index];
            if (!partResults) return;
            if (part.writing) {
                reviewWritingPart(part, partResults);
                return;
            }
            decorate(part, partResults);
            renderExplanations(part, partResults, state.mode !== 'study');
            if (part.listening) renderTranscript(part);
            else renderPassageNotes(part);
            renderResultCard(part, partResults);
        });
        $('submit-label').textContent = 'Finish';
        renderTimer();
        switchPart(state.currentPart, false);
        syncReviewToggle();
        state.parts.forEach((part) => { part.questions.scrollTop = 0; });
    }

    function reviewWritingPart(part, results) {
        part.textarea.readOnly = true;
        updateWordCount(part);
        updateNavStatus(part);
        if (part.exam.essay && !part.passage.querySelector('.model-answer')) {
            const block = el('div', 'model-answer');
            block.appendChild(el('h3', null, 'Model answer · 参考范文'));
            String(part.exam.essay).split(/\n+/).map(cleanText).filter(Boolean)
                .forEach((paragraph) => block.appendChild(el('p', null, paragraph)));
            block.appendChild(el('p', 'model-count', countWords(part.exam.essay) + ' words'));
            part.passage.appendChild(block);
        }
        renderResultCard(part, results);
    }

    // ------------------------------------------------------------------
    // 听力：播放器与录音原文
    // ------------------------------------------------------------------
    const audio = new Audio();
    audio.preload = 'auto';
    const RATES = [1, 1.25, 1.5, 0.75];
    const player = {
        part: null,
        seeking: false,
        pendingTime: 0,
        rateIndex: 0,

        reset() {
            audio.pause();
            this.part = null;
            this.pendingTime = 0;
            this.render();
        },

        load(part) {
            if (this.part === part) return;
            const wasPlaying = !audio.paused;
            audio.pause();
            this.part = part;
            if (!part.audioSrc) {
                audio.removeAttribute('src');
                toast('该 Section 没有音频');
            } else if (audio.getAttribute('src') !== part.audioSrc) {
                audio.src = part.audioSrc;
                audio.load();
            }
            audio.playbackRate = RATES[this.rateIndex];
            if (wasPlaying && state.mode === 'test') this.play();
            this.render();
        },

        play() {
            if (!audio.getAttribute('src')) return;
            const promise = audio.play();
            if (promise && promise.catch) {
                promise.catch(() => toast('音频无法播放：请检查网络，或先在 App 中下载本套音频'));
            }
        },

        toggle() {
            if (audio.paused) this.play();
            else audio.pause();
        },

        seekBy(seconds) {
            if (!isFinite(audio.duration)) return;
            audio.currentTime = Math.min(Math.max(audio.currentTime + seconds, 0), audio.duration);
        },

        render() {
            const duration = isFinite(audio.duration) ? audio.duration : 0;
            const current = audio.currentTime || 0;
            $('ap-time').textContent = formatClock(current) + ' / ' + formatClock(duration);
            if (!this.seeking) $('ap-seek').value = duration ? Math.round((current / duration) * 1000) : 0;
            $('audio-player').classList.toggle('playing', !audio.paused);
            $('ap-rate').textContent = RATES[this.rateIndex].toFixed(2).replace(/0$/, '') + '×';
        },
    };

    $('ap-play').addEventListener('click', () => player.toggle());
    $('ap-back').addEventListener('click', () => player.seekBy(-5));
    $('ap-forward').addEventListener('click', () => player.seekBy(5));
    $('ap-rate').addEventListener('click', () => {
        player.rateIndex = (player.rateIndex + 1) % RATES.length;
        audio.playbackRate = RATES[player.rateIndex];
        player.render();
    });
    $('ap-seek').addEventListener('input', () => {
        player.seeking = true;
        if (isFinite(audio.duration)) {
            const target = ($('ap-seek').value / 1000) * audio.duration;
            $('ap-time').textContent = formatClock(target) + ' / ' + formatClock(audio.duration);
        }
    });
    $('ap-seek').addEventListener('change', () => {
        if (isFinite(audio.duration)) audio.currentTime = ($('ap-seek').value / 1000) * audio.duration;
        player.seeking = false;
    });
    audio.addEventListener('loadedmetadata', () => {
        if (player.part && isFinite(audio.duration)) player.part.duration = audio.duration;
        if (player.pendingTime && isFinite(audio.duration)) {
            audio.currentTime = Math.min(player.pendingTime, audio.duration);
            player.pendingTime = 0;
        }
        player.render();
    });
    ['play', 'pause', 'durationchange'].forEach((name) => audio.addEventListener(name, () => player.render()));
    audio.addEventListener('timeupdate', () => {
        player.render();
        highlightTranscript();
    });
    audio.addEventListener('ended', () => {
        player.render();
        // 整套听力：一个 Part 播完后自动进入下一个 Part，与正式考试一致
        if (state.mode === 'test' && player.part && player.part.index < state.parts.length - 1) {
            const next = state.parts[player.part.index + 1];
            if (isStrictListening()) player.load(next);
            switchPart(next.index, true);
            player.play();
            toast('Part ' + next.label);
        } else if (isStrictListening() && !state.listeningReview.started) {
            state.listeningReview = { started: true, elapsed: 0 };
            renderTimer();
            toast('You now have 2 minutes to check your answers.', 5000);
        }
    });
    audio.addEventListener('error', () => {
        if (audio.getAttribute('src')) toast('音频加载失败：请检查网络，或先在 App 中下载本套音频');
    });

    function renderTranscript(part) {
        if (!part.transcript.length) {
            part.passage.innerHTML = '<p class="missing-image">本 Section 没有录音原文</p>';
            return;
        }
        part.passage.innerHTML = '';
        part.passage.appendChild(el('h2', null, 'Transcript · Part ' + part.label));
        part.passage.appendChild(el('p', 'tx-hint', '点按任一句即可从该处播放。'));
        part.transcript.forEach((line) => {
            const row = el('div', 'tx-line');
            row.dataset.start = String(line.start || 0);
            row.dataset.end = String(line.end || 0);
            row.appendChild(el('span', 'tx-time', formatClock((line.start || 0) / 1000)));
            const text = el('div', 'tx-text');
            text.appendChild(el('div', 'tx-en', line.en || ''));
            if (line.zh) text.appendChild(el('div', 'tx-zh', line.zh));
            row.appendChild(text);
            row.addEventListener('click', () => {
                const selection = window.getSelection();
                if (selection && !selection.isCollapsed) return;
                if (player.part !== part) player.load(part);
                audio.currentTime = (line.start || 0) / 1000;
                player.play();
            });
            part.passage.appendChild(row);
        });
    }

    let currentTranscriptLine = null;
    function highlightTranscript() {
        const part = player.part;
        if (!part || !part.listening || !document.body.classList.contains('reviewing')) return;
        const ms = (audio.currentTime || 0) * 1000;
        const line = Array.from(part.passage.querySelectorAll('.tx-line')).find((row) =>
            ms >= Number(row.dataset.start) && ms < Number(row.dataset.end || Infinity));
        if (line === currentTranscriptLine) return;
        if (currentTranscriptLine) currentTranscriptLine.classList.remove('current');
        currentTranscriptLine = line || null;
        if (line) {
            line.classList.add('current');
            if (!audio.paused) line.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
        }
    }

    // ------------------------------------------------------------------
    // 公共接口
    // ------------------------------------------------------------------
    function start(config) {
        state.config = config || {};
        state.mode = config.mode || 'test';
        state.preferences = Object.assign(state.preferences, config.preferences || {});
        // 重新开始（重新练习、模考进入下一部分）时清空上一次的状态
        state.submitted = false;
        state.results = null;
        state.waitingStart = false;
        state.listeningReview = { started: false, elapsed: 0 };
        state.reviews = new Set();
        document.body.classList.remove('reviewing', 'show-translation', 'intro-open');
        $('intro').hidden = true;
        $('finish').hidden = true;
        toggleMenu(false);
        $('candidate-id').textContent = config.candidateId || '—';

        workspace.querySelectorAll('.part-view').forEach((view) => view.remove());
        state.parts = (config.parts || []).map((partConfig, index) => buildPart(partConfig, index));
        renderNav();

        const timerConfig = config.timer || {};
        state.timer.kind = timerConfig.kind || 'countdown';
        state.timer.limit = timerConfig.limit || 1200;
        state.timer.elapsed = 0;
        state.timer.paused = false;

        const draft = state.mode === 'test' ? config.draft : null;
        if (draft) {
            (draft.parts || []).forEach((partDraft, index) => {
                const part = state.parts[index];
                if (!part) return;
                Object.keys(partDraft.answers || {}).forEach((qid) => setAnswer(part, qid, partDraft.answers[qid]));
                updateNavStatus(part);
            });
            restoreHighlights(draft.highlights);
            state.reviews = new Set(draft.reviews || []);
            state.parts.forEach(updateNavStatus);
            state.timer.elapsed = draft.elapsed || 0;
            state.timer.paused = !!draft.paused && !isStrict();
            if (draft.reviewElapsed != null) state.listeningReview = { started: true, elapsed: draft.reviewElapsed };
        }

        const listeningMode = state.parts.some((part) => part.listening);
        const strictListening = isStrictListening();
        document.body.classList.toggle('listening-mode', listeningMode);
        document.body.classList.toggle('writing-mode', state.parts.some((part) => part.writing));
        document.body.classList.toggle('strict-mode', isStrict());
        $('audio-player').hidden = !listeningMode || strictListening;
        timerButton.hidden = listeningMode && !strictListening;
        player.reset();
        if (strictListening) preloadDurations();
        if (draft && draft.audioTime) player.pendingTime = draft.audioTime;

        applyPreferences();
        switchPart(Math.min((draft && draft.currentPart) || 0, state.parts.length - 1), true);
        startTimer();

        if (state.mode === 'review' && config.review) {
            state.timer.elapsed = config.review.results.elapsed || 0;
            enterReview(config.review.results, config.review.parts);
            restoreHighlights(config.review.highlights);
        } else if (state.mode === 'study') {
            const results = { parts: state.parts.map((part) => buildStudyResults(part)), score: 0, total: 0 };
            enterReview(results, results.parts.map((partResult) => ({ answers: partResult.answers })));
        }
        if (state.mode === 'test') {
            document.querySelector('.ielts-header').setAttribute('data-mode', 'test');
        }
        $('submit-label').textContent = state.mode === 'test' ? 'Submit' : 'Finish';

        // 说明页：整套练习与模考开始前显示，点击 Start test 后才开始计时与播放录音
        if (state.mode === 'test' && !draft && config.intro) {
            showIntro(config.intro);
        } else if (strictListening && !state.listeningReview.started) {
            beginStrictListening(draft ? (draft.audioPart || 0) : 0);
        }
        post('started', { parts: state.parts.length });
    }

    function fillList(id, items) {
        const list = $(id);
        list.innerHTML = '';
        (items || []).forEach((item) => list.appendChild(el('li', null, item)));
        list.previousElementSibling.hidden = !(items || []).length;
    }

    function showIntro(intro) {
        state.waitingStart = true;
        $('intro-title').textContent = intro.title || '';
        $('intro-time').textContent = intro.time ? 'Time: ' + intro.time : '';
        fillList('intro-instructions', intro.instructions);
        fillList('intro-information', intro.information);
        $('intro-start').textContent = intro.button || 'Start test';
        $('intro').hidden = false;
        document.body.classList.add('intro-open');
        syncReviewToggle();
        renderTimer();
    }

    $('intro-start').addEventListener('click', () => {
        $('intro').hidden = true;
        document.body.classList.remove('intro-open');
        state.waitingStart = false;
        state.timer.last = performance.now();
        syncReviewToggle();
        if (isStrictListening()) beginStrictListening(0);
        renderTimer();
        flushDraft();
    });

    function beginStrictListening(index) {
        const part = state.parts[Math.min(index, state.parts.length - 1)];
        if (!part) return;
        player.load(part);
        if (state.currentPart !== part.index) switchPart(part.index, true);
        player.play();
    }

    function preloadDurations() {
        state.parts.forEach((part) => {
            if (!part.audioSrc || part.duration) return;
            const probe = new Audio();
            probe.preload = 'metadata';
            probe.addEventListener('loadedmetadata', () => {
                if (isFinite(probe.duration)) {
                    part.duration = probe.duration;
                    renderTimer();
                }
                probe.removeAttribute('src');
                probe.load();
            }, { once: true });
            probe.src = part.audioSrc;
        });
    }

    /** 模考全部结束：显示结束页，点击后回到 App 查看成绩 */
    function finish(info) {
        info = info || {};
        state.submitted = true;
        state.timer.paused = true;
        player.reset();
        timerButton.hidden = true;
        $('finish-title').textContent = info.title || 'The test is now finished';
        $('finish-message').textContent = info.message || '';
        $('finish-button').textContent = info.button || 'View results';
        $('finish').hidden = false;
        document.body.classList.add('intro-open');
    }

    $('finish-button').addEventListener('click', () => post('exit', { inProgress: false, finished: true }));

    function buildStudyResults(part) {
        const questions = {};
        const answers = {};
        const key = part.exam.answerKey || {};
        part.multiGroups.forEach((entry) => {
            const all = [];
            entry.qids.forEach((qid) => (key[qid] || []).forEach((value) => { if (!all.includes(value)) all.push(value); }));
            all.sort().forEach((value, index) => { if (entry.qids[index]) answers[entry.qids[index]] = value; });
        });
        part.order.forEach((qid) => {
            const expected = key[qid] || [];
            questions[qid] = { correct: true, expected, given: expected[0] || '' };
            if (!answers[qid] && expected[0] != null) answers[qid] = expected[0];
        });
        return { questions, answers, score: 0, total: part.order.length };
    }

    function showResults(results) {
        state.mode = 'review';
        state.submitted = true;
        if (results && results.elapsed != null) state.timer.elapsed = results.elapsed;
        enterReview(results, null);
    }

    window.ExamEngine = {
        key: (key, shift) => handleKey(key, !!shift, document.activeElement),
        start,
        finish,
        showResults,
        highlightSelection,
        selectionInfo,
        flushDraft,
        requestSubmit: () => submit(false),
        requestExit,
        toast,
    };

    post('ready');

    // 开发预览：浏览器中直接打开 exam.html?dev=<examId>[,<examId>…]&mode=test|study
    if (!bridge) {
        const params = new URLSearchParams(location.search);
        const ids = (params.get('dev') || '').split(',').filter(Boolean);
        if (ids.length) {
            // 形如 bank/reading:c10-test1-p1 或 bank/listening:c10-test1-l1
            const load = (spec) => {
                const [base, id] = spec.includes(':') ? spec.split(':') : ['reading', spec];
                if (base === 'writing') {
                    // 形如 writing:c18-test1-w1
                    return fetch('content/bank/index.json').then((r) => r.json()).then((index) => {
                        const task = index.writing.find((item) => item.id === id);
                        return { exam: Object.assign({ skill: 'writing' }, task, {
                            image: task.image ? 'content/bank/images/' + task.image : null,
                        }) };
                    });
                }
                return Promise.all([
                    fetch('content/' + base + '/exams/' + id + '.json').then((r) => r.json()),
                    fetch('content/' + base + '/explanations/' + id + '.json').then((r) => (r.ok ? r.json() : null)).catch(() => null),
                ]).then(([exam, explanation]) => ({ exam, explanation }));
            };
            Promise.all(ids.map(load)).then((parts) => start({
                mode: params.get('mode') || 'test',
                parts,
                timer: { kind: params.get('strict') ? 'none' : 'countdown', limit: 1200 * parts.length },
                strict: !!params.get('strict'),
                intro: params.get('intro') ? {
                    title: 'IELTS Practice', time: '1 hour',
                    instructions: ['Answer all the questions.'], information: ['There are 40 questions in this test.'],
                } : null,
                candidateId: '0000 0000',
                actions: { retry: true, next: true },
            }));
        }
    }
})();
