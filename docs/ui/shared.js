/* Horae 设计原型共用：演示数据、状态规则与措辞、标志图形、桌面外框与页面装配。
   ledger.html 只负责把这份数据画成弹窗。 */
(function () {
  'use strict';

  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

  // ---------- 标志：字母 H。菜单栏里有四种状态，只靠形状区分；弹窗里的标志固定用 idle ----------
  const svg = (inner, w) =>
    `<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="${w || 1.5}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${inner}</svg>`;
  const dot = (x, y, r) => `<circle cx="${x}" cy="${y}" r="${r}" fill="currentColor" stroke="none"/>`;
  const marks = {
    idle: svg('<path d="M4.5 3v10M11.5 3v10M4.5 8h7"/>', 2),
    // 运行：横梁上有点在走
    running: svg('<path d="M4.5 3v10M11.5 3v10"/><path class="hz-bridge" d="M4.5 8h7"/>', 2),
    // 需要处理：右柱变成叹号
    failed: svg('<path d="M4.5 3v10M11.5 3v6M4.5 8h7"/>' + dot(11.5, 12.6, 1.15), 2),
    // 已暂停：没有横梁
    paused: svg('<path d="M4.5 3v10M11.5 3v10"/>', 2),
  };

  // ---------- 图标：16 格、1.5 线宽、圆头 ----------
  const ICONS = {
    chevR: '<path d="M6 3.5 10.5 8 6 12.5"/>',
    chevL: '<path d="M10 3.5 5.5 8 10 12.5"/>',
    chevD: '<path d="M3.5 6 8 10.5 12.5 6"/>',
    updown: '<path d="M5.2 6.3 8 3.5l2.8 2.8M5.2 9.7 8 12.5l2.8-2.8"/>',
    more: dot(3.5, 8, 1.1) + dot(8, 8, 1.1) + dot(12.5, 8, 1.1),
    folder: '<path d="M2 4.6a1.1 1.1 0 0 1 1.1-1.1h2.8L7.4 5h5.5A1.1 1.1 0 0 1 14 6.1v5.8a1.1 1.1 0 0 1-1.1 1.1H3.1A1.1 1.1 0 0 1 2 11.9z"/>',
    out: '<path d="M6.5 4H12v5.5M12 4l-7.5 7.5"/>',
    plus: '<path d="M8 3.5v9M3.5 8h9"/>',
    sliders: '<path d="M2.5 5h6M13 5h.5M2.5 11H3M7.5 11h6"/><circle cx="10.8" cy="5" r="1.7"/><circle cx="5.2" cy="11" r="1.7"/>',
    copy: '<rect x="5.5" y="5.5" width="8" height="8" rx="1.6"/><path d="M10.5 3.2a1.4 1.4 0 0 0-1.2-.7H4.1A1.6 1.6 0 0 0 2.5 4.1v5.2a1.4 1.4 0 0 0 .7 1.2"/>',
    trash: '<path d="M3 4.5h10M6.5 4.5V3h3v1.5M4.4 4.5l.6 8.5h6l.6-8.5"/>',
    doc: '<path d="M4 2.5h5.5L12 5v8.5H4zM9.5 2.5V5H12M6 8h4M6 10.5h4"/>',
    pause: '<path d="M6 4v8M10 4v8"/>',
    play: '<path d="M5.5 3.8v8.4l7-4.2z"/>',
    log: '<path d="M4 2.5h5.5L12 5v8.5H4zM9.5 2.5V5H12M6 8h4M6 10.5h4"/>',
    // 齿轮：一圈粗虚线做齿，里面一个环
    gear: '<circle cx="8" cy="8" r="5.3" stroke-width="2.2" stroke-dasharray="2.08 2.08" stroke-linecap="butt"/><circle cx="8" cy="8" r="3.4"/>',
    stack: '<path d="M8 2.5 13.5 5.2 8 8 2.5 5.2zM2.5 8 8 10.8 13.5 8M2.5 10.8 8 13.5l5.5-2.7"/>',
    bell: '<path d="M8 2.5A3.5 3.5 0 0 0 4.5 6v2.3l-1.2 2.2h9.4l-1.2-2.2V6A3.5 3.5 0 0 0 8 2.5zM6.6 12.6a1.5 1.5 0 0 0 2.8 0"/>',
    power: '<path d="M8 2.5v5M4.9 4.4a4.6 4.6 0 1 0 6.2 0"/>',
    download: '<path d="M8 3v7M5 7.5l3 3 3-3M3.5 13h9"/>',
  };
  const icon = (name) => svg(ICONS[name]);

  // ---------- 来源的品牌小图标：与 app 的 SourceIcon.iconKey 同一套规则，直接用 app/Icons 里的图 ----------
  function iconKey(id) {
    const k = id.toLowerCase();
    if (k.includes('hermes')) return 'hermes';
    if (k.includes('brew')) return 'brew';
    if (k.includes('npm')) return 'npm';
    if (k.includes('claude')) return 'claude';
    if (k.includes('codex') || k.includes('openai')) return 'codex';
    if (k.includes('rust') || k.includes('cargo')) return 'rustup';
    if (k.includes('pipx') || k.includes('pip') || k.includes('python')) return 'pipx';
    if (k.includes('node')) return 'node';
    return 'generic';
  }
  const brand = (id, cls) => `<img class="${cls || 'ic'}" src="../../app/Icons/${iconKey(id)}.png" alt="">`;

  // ---------- 演示数据 ----------
  // [id, 名称, 周期数值, 周期单位, 命令]
  const DEFS = [
    ['brew', 'Homebrew', 8, '小时', 'brew update && brew upgrade && brew cleanup'],
    ['brew-cask', 'Homebrew Cask', 1, '天', 'brew upgrade --cask --greedy'],
    ['npm-globals', 'npm 全局包', 8, '小时', 'npx npm-check-updates -g -u && npm update -g'],
    ['claude-code', 'Claude Code', 6, '小时', 'claude update'],
    ['codex', 'Codex', 6, '小时', 'npm install -g @openai/codex@latest'],
    ['hermes', 'Hermes', 1, '天', 'hermes update --yes --channel stable'],
    ['rustup', 'Rust 工具链', 1, '周', 'rustup update'],
    ['pipx', 'pipx', 1, '天', 'pipx upgrade-all'],
  ];
  // 压力数据：来源增多 + 长名称
  const EXTRA = [
    ['ai-dev-clis', 'AI/dev CLI (claude-code / codex / skills / codegraph)', 6, '小时', 'npm update -g @anthropic-ai/claude-code @openai/codex'],
    ['go-tools', 'Go-installed CLI tools (go install @latest)', 1, '周', 'for t in golangci-lint gofumpt goimports; do go install "$t@latest"; done'],
    ['mas', 'Mac App Store apps (mas)', 1, '天', 'mas upgrade'],
    ['gcloud', 'Google Cloud SDK components', 1, '周', 'gcloud components update --quiet'],
    ['gem', 'Ruby user gems (gem)', 1, '周', 'gem update --user-install'],
  ];

  // 同一轮运行里的来源共用一个时间戳（引擎在一轮开始时取一次 now）。
  const IDLE = {
    brew: { status: 'success', last: '12:04', dur: '48 秒', next: '20:04' },
    'brew-cask': { status: 'success', last: '09:12', dur: '2 分 31 秒', next: '明天 09:12' },
    'npm-globals': { status: 'success', last: '12:04', dur: '21 秒', next: '20:04' },
    'claude-code': { status: 'success', last: '12:04', dur: '9 秒', next: '18:04' },
    codex: { status: 'success', last: '12:04', dur: '7 秒', next: '18:04' },
    hermes: { status: 'success', last: '09:12', dur: '12 秒', next: '明天 09:12' },
    rustup: { status: 'success', last: '11-09', dur: '34 秒', next: '11-16' },
    pipx: { status: 'success', last: '10-28', dur: '15 秒', next: null, enabled: false },
    'ai-dev-clis': { status: 'success', last: '12:04', dur: '18 秒', next: '18:04' },
    'go-tools': { status: 'success', last: '11-10', dur: '1 分 12 秒', next: '11-17' },
    mas: { status: 'success', last: '09:12', dur: '41 秒', next: '明天 09:12' },
    gcloud: { status: 'never', last: null, dur: null, next: null, due: true },
    gem: { status: 'success', last: '11-08', dur: '26 秒', next: '11-15' },
  };

  const RUST_TAIL = [
    "info: syncing channel updates for 'stable-aarch64-apple-darwin'",
    "error: could not download file from 'https://static.rust-lang.org/dist/channel-rust-stable.toml.sha256'",
    'error: caused by: failed to make network request: operation timed out',
  ];
  const NPM_TAIL = [
    '$ npx npm-check-updates -g -u && npm update -g',
    'npm http fetch GET 200 https://registry.npmjs.org/typescript 412ms (cache revalidated)',
    'npm http fetch GET https://registry.npmjs.org/@biomejs%2fbiome attempt 3 failed with ETIMEDOUT',
  ];
  const BREW_LINES = [
    '$ brew update && brew upgrade && brew cleanup',
    '==> Updating Homebrew...',
    '==> Upgrading 3 outdated packages:',
    'gh 2.83.0 -> 2.83.1, ripgrep 15.1.0 -> 15.1.1, uv 0.11.20 -> 0.11.22',
    '==> Pouring ripgrep--15.1.1.arm64_tahoe.bottle.tar.gz',
  ];

  const STATES = {
    idle: { name: '常态', now: '14:32', lastRun: { at: '12:05', ran: 4, ok: 4, bad: 0 }, patch: {} },
    running: {
      name: '执行与排队',
      now: '20:06',
      lastRun: { at: '18:05', ran: 2, ok: 2, bad: 0 },
      current: { id: 'brew', index: 1, total: 2, elapsed: 72, lines: BREW_LINES },
      patch: {
        brew: { activity: 'running' },
        'npm-globals': { due: true },
        'claude-code': { activity: 'queued', last: '18:04', next: '明天 00:04' },
        codex: { last: '18:04', next: '明天 00:04' },
        'ai-dev-clis': { last: '18:04', next: '明天 00:04' },
      },
    },
    failed: {
      name: '失败',
      now: '14:32',
      lastRun: { at: '12:20', ran: 4, ok: 3, bad: 1 },
      patch: {
        'npm-globals': { status: 'timeout', last: '12:19', dur: '15 分', lastOk: '04:04', next: '20:04', word: '超时', reason: '15 分钟后被终止', tail: NPM_TAIL },
        rustup: { status: 'failure', exit: 1, last: '09:16', dur: '1 分 03 秒', lastOk: '11-06', next: '11-20', word: '失败', reason: '退出码 1', tail: RUST_TAIL },
      },
    },
    paused: {
      name: '已暂停',
      now: '14:32',
      lastRun: { at: '12:05', ran: 4, ok: 4, bad: 0 },
      paused: { until: '明天 00:00' },
      // 暂停期间，下次最早 = max(到期时刻, 暂停结束时刻)
      patch: {
        brew: { next: '明天 00:00', shifted: true },
        'npm-globals': { next: '明天 00:00', shifted: true },
        'claude-code': { next: '明天 00:00', shifted: true },
        codex: { next: '明天 00:00', shifted: true },
        'ai-dev-clis': { next: '明天 00:00', shifted: true },
      },
    },
  };

  function logRows(state) {
    const F = state === 'failed';
    const R = state === 'running';
    const rows = [];
    if (R) rows.push(['今天', '18:05', 'codex', 'success', '7 秒'], ['今天', '18:04', 'claude-code', 'success', '10 秒']);
    if (F) {
      rows.push(
        ['今天', '12:20', 'codex', 'success', '7 秒'],
        ['今天', '12:19', 'claude-code', 'success', '9 秒'],
        ['今天', '12:19', 'npm-globals', 'timeout', '15 分', '15 分钟后被终止', NPM_TAIL],
        ['今天', '12:04', 'brew', 'success', '48 秒'],
        ['今天', '09:16', 'rustup', 'failure', '1 分 03 秒', '退出码 1', RUST_TAIL]
      );
    } else {
      rows.push(
        ['今天', '12:05', 'codex', 'success', '7 秒'],
        ['今天', '12:05', 'claude-code', 'success', '9 秒'],
        ['今天', '12:05', 'npm-globals', 'success', '21 秒'],
        ['今天', '12:04', 'brew', 'success', '48 秒']
      );
    }
    rows.push(
      ['今天', '09:15', 'hermes', 'success', '12 秒'],
      ['今天', '09:14', 'brew-cask', 'success', '2 分 31 秒'],
      ['今天', '06:04', 'codex', 'success', '6 秒'],
      ['今天', '06:04', 'claude-code', 'success', '11 秒'],
      ['今天', '04:05', 'npm-globals', 'success', '19 秒'],
      ['今天', '04:04', 'brew', 'success', '37 秒'],
      ['昨天', '20:05', 'npm-globals', 'success', '20 秒'],
      ['昨天', '20:04', 'brew', 'success', '52 秒'],
      ['昨天', '18:04', 'codex', 'success', '8 秒'],
      ['昨天', '18:04', 'claude-code', 'success', '9 秒'],
      ['昨天', '09:14', 'hermes', 'success', '14 秒'],
      ['昨天', '09:13', 'brew-cask', 'success', '1 分 48 秒']
    );
    const names = Object.fromEntries(DEFS.concat(EXTRA).map((d) => [d[0], d[1]]));
    return rows.map((r) => ({ day: r[0], time: r[1], id: r[2], label: names[r[2]], status: r[3], dur: r[4], reason: r[5] || '', tail: r[6] || [] }));
  }

  const PRESETS = [
    { label: 'Go-installed CLI tools (go install @latest)', cadence: '每 7 天', installed: true, detail: 'go 1.26.4，$GOPATH/bin 下 4 个工具' },
    { label: 'npm 自身', cadence: '每 7 天', installed: true, detail: 'npm 11.17.0，~/.npm-global' },
    { label: 'pnpm / corepack', cadence: '每 7 天', installed: true, detail: 'corepack 0.35.0' },
    { label: 'Mac App Store apps (mas)', cadence: '每天', installed: false, detail: '未找到 mas' },
    { label: 'Google Cloud SDK components', cadence: '每 7 天', installed: false, detail: '未找到 gcloud' },
    { label: 'mise-managed tool versions', cadence: '每 7 天', installed: false, detail: '未找到 mise' },
  ];

  function scenario(state, data) {
    const S = STATES[state] || STATES.idle;
    const defs = data === 'stress' ? DEFS.concat(EXTRA) : DEFS;
    const sources = defs.map((d) => {
      const s = Object.assign(
        { id: d[0], label: d[1], n: d[2], unit: d[3], cadence: '每' + (d[2] === 1 ? '' : ' ' + d[2] + ' ') + d[3], cmd: d[4], enabled: true, activity: null, due: false, shifted: false },
        IDLE[d[0]],
        S.patch[d[0]]
      );
      s.bad = s.enabled && (s.status === 'failure' || s.status === 'timeout');
      return s;
    });
    const have = new Set(sources.map((s) => s.label));
    return {
      state: STATES[state] ? state : 'idle',
      name: S.name,
      now: S.now,
      paused: S.paused || null,
      current: S.current || null,
      lastRun: S.lastRun,
      sources,
      log: logRows(state),
      presets: PRESETS.filter((p) => !have.has(p.label)),
    };
  }

  // ---------- 共同规则：措辞 ----------
  const day = (t) => (/^\d\d:\d\d$/.test(t) ? '今天 ' + t : t);
  const elapsed = (sec) => {
    const m = Math.floor(sec / 60);
    const s = sec % 60;
    return m > 0 ? m + ' 分 ' + String(s).padStart(2, '0') + ' 秒' : s + ' 秒';
  };
  const elapsedTag = (sec) => `<span class="num" data-elapsed="${sec}">${elapsed(sec)}</span>`;

  // 两段文字相接：拉丁字母或数字与汉字相邻时留一个空格（“Homebrew 更新失败”），两边都是汉字时直接相连。
  const adjoin = (a, b) => (/[A-Za-z0-9]$/.test(a) && /^[\u4e00-\u9fff]/.test(b)) || (/[\u4e00-\u9fff]$/.test(a) && /^[A-Za-z0-9]/.test(b)) ? a + ' ' + b : a + b;

  // 总述：运行中 > 有失败 > 已暂停 > 全部正常。暂停另有常驻提示，不只靠这句话。
  function verdict(sc) {
    const bad = sc.sources.filter((s) => s.bad);
    const lr = sc.lastRun;
    const lastLine = '最近一次运行 ' + lr.at + '，' + lr.ok + ' 项成功' + (lr.bad ? '、' + lr.bad + ' 项未成功' : '');
    if (sc.current) {
      const s = sc.sources.find((x) => x.id === sc.current.id);
      return {
        kind: 'running',
        title: '正在更新 ' + s.label,
        sub: '第 ' + sc.current.index + '/' + sc.current.total + ' 项，已用 ' + elapsedTag(sc.current.elapsed) + (bad.length ? '，' + bad.length + ' 项未成功' : ''),
      };
    }
    if (bad.length === 1) return { kind: 'failed', title: adjoin(bad[0].label, '更新' + bad[0].word), sub: bad[0].reason + '，' + day(bad[0].last) };
    if (bad.length > 1) return { kind: 'failed', title: bad.length + ' 项需要处理', sub: bad.map((s) => adjoin(s.label, s.word)).join('、') };
    if (sc.paused) return { kind: 'paused', title: '自动更新已暂停', sub: sc.paused.until + ' 恢复，手动更新不受影响' };
    return { kind: 'idle', title: '全部正常', sub: lastLine };
  }

  // 单个来源的主状态：停用 > 正在更新 > 排队 > 失败/超时 > 尚未运行 > 成功
  function kindOf(s) {
    if (!s.enabled) return 'disabled';
    if (s.activity) return s.activity;
    if (s.bad) return 'bad';
    if (s.status === 'never') return 'never';
    return 'ok';
  }
  // “下次最早”一栏的文字。暂停期间取到期时刻与暂停结束中较晚的一个，所以已到期的来源写暂停结束的时刻。
  function nextText(s, sc) {
    if (!s.enabled) return '已停用';
    if (s.due) return sc.paused ? sc.paused.until : '已到期';
    return s.next || '已到期';
  }
  const shifted = (s, sc) => s.enabled && (s.shifted || (s.due && !!sc.paused));

  // ---------- 页面装配 ----------
  function params() {
    const q = new URLSearchParams(location.search);
    return {
      embed: q.get('embed') === '1',
      state: q.get('state') || 'idle',
      page: q.get('page') || 'main',
      theme: q.get('theme') || 'light',
      data: q.get('data') || 'base',
      id: q.get('id') || '',
    };
  }

  const t0 = Date.now();
  function tick() {
    const d = Math.floor((Date.now() - t0) / 1000);
    document.querySelectorAll('[data-elapsed]').forEach((el) => {
      el.textContent = elapsed(Number(el.dataset.elapsed) + d);
    });
  }

  function frame(cfg, view) {
    const el = document.createElement('section');
    el.className = 'frame';
    el.innerHTML = '<div class="desk"><div class="menubar"><span class="mb-icon"></span><span class="mb-clock"></span></div><div class="popwrap"><div class="host"></div></div></div>';
    const host = el.querySelector('.host');
    const icon = el.querySelector('.mb-icon');
    const clock = el.querySelector('.mb-clock');
    const paint = () => {
      const sc = scenario(view.state, view.data);
      host.innerHTML = cfg.render(view, sc);
      icon.innerHTML = marks[verdict(sc).kind];
      clock.textContent = '11月13日 周五 ' + sc.now;
      tick();
    };
    host.addEventListener('click', (e) => {
      const t = e.target.closest('[data-nav],[data-toggle],[data-set]');
      if (!t) return;
      if (t.dataset.nav) {
        view.page = t.dataset.nav;
        const keep = t.dataset.keep ? { [t.dataset.keep.split('=')[0]]: t.dataset.keep.split('=')[1] } : {};
        view.ui = keep;
      } else if (t.dataset.toggle) {
        view.ui[t.dataset.toggle] = !view.ui[t.dataset.toggle];
      } else {
        const [k, v] = t.dataset.set.split('=');
        view.ui[k] = view.ui[k] === v ? null : v;
      }
      paint();
    });
    paint();
    return el;
  }

  // 按地址参数画一个弹窗：state、page、theme、data，以及 hover（让某一行显示悬停态）。
  // 入口页用 iframe 把各个状态摆在一起，embed=1 时把内容高度告诉它。
  function mount(cfg) {
    const p = params();
    const q = new URLSearchParams(location.search);
    document.documentElement.dataset.theme = p.theme;
    const root = document.getElementById('root');
    root.appendChild(frame(cfg, { state: p.state, page: p.page, data: p.data, ui: q.get('hover') ? { hover: q.get('hover') } : {} }));
    if (p.embed) {
      document.body.classList.add('embed');
      const report = () => parent.postMessage({ horae: p.id, height: Math.ceil(root.getBoundingClientRect().height) }, '*');
      new ResizeObserver(report).observe(root);
    }
    setInterval(tick, 1000);
  }

  window.Horae = { esc, marks, icon, brand, scenario, verdict, kindOf, nextText, shifted, day, elapsed, elapsedTag, mount, params, STATES };
})();
