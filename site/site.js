(() => {
  'use strict';
  const config = window.HANX_SITE || {};
  const unresolved = value => !value || /HANX_/.test(value);
  const repoReady = !unresolved(config.owner) && !unresolved(config.repository);
  const repository = repoReady ? `https://github.com/${encodeURIComponent(config.owner)}/${encodeURIComponent(config.repository)}` : null;
  function setLinks(selector, url) {
    if (!url) return;
    document.querySelectorAll(selector).forEach(link => {
      link.href = url;
      link.hidden = false;
    });
  }
  setLinks('[data-guide]', config.guide || './cli/');
  setLinks('[data-repo]', repository);
  setLinks('[data-releases]', repository && `${repository}/releases`);
  setLinks('[data-license]', repository && `${repository}/blob/main/${config.licensePath || 'LICENSE'}`);
  setLinks('[data-provenance]', repository && `${repository}/blob/main/${config.provenancePath || 'PROVENANCE.md'}`);

  const channels = {
    npm: { ready: config.npm?.available && !unresolved(config.npm.package), command: `npm install -g ${config.npm?.package || ''}\nhanx setup`, title: 'npm으로 앱과 CLI 설치', pending: 'npm 배포 준비 중', detail: config.npm?.package?.startsWith('https://') ? 'GitHub 릴리스의 npm 패키지를 직접 설치합니다. npm 레지스트리 등록은 진행 중입니다. Node.js 18 이상이 필요합니다.' : '설치 후 방향키로 GUI만, CLI만, 둘 다를 선택합니다. Node.js 18 이상이 필요합니다.' },
    brew: { ready: config.brew?.available && !unresolved(config.brew.formula), command: `brew install ${config.brew?.formula || ''}\nhanx setup`, title: 'Homebrew로 앱과 CLI 설치', pending: 'Homebrew 배포 준비 중', detail: 'macOS와 Linux에서 설치합니다. hanx setup에서 GUI와 CLI 구성을 고르세요. Windows에서는 npm 또는 Setup.exe를 사용하세요.' },
    pkg: { ready: config.pkg?.available && repoReady && !unresolved(config.pkg.asset), title: `HanX ${config.version || ''} Mac 설치 패키지`, pending: '설치 패키지 배포 준비 중', detail: '설치 파일을 열고 안내를 따르세요. GUI 앱과 같은 버전의 CLI를 함께 설치합니다.' }
  };
  Object.entries(channels).forEach(([key, channel]) => {
    const status = document.querySelector(`[data-channel-status="${key}"]`);
    status.textContent = channel.ready ? channel.title : channel.pending;
    if (!channel.ready) return;
    document.querySelector(`[data-channel-detail="${key}"]`).textContent = channel.detail;
    if (channel.command) {
      document.getElementById(`command-${key}`).textContent = channel.command;
      document.querySelector(`[data-command-wrap="${key}"]`).hidden = false;
    } else {
      const download = document.getElementById('pkg-download');
      download.href = `${repository}/releases/download/v${encodeURIComponent(config.version)}/${encodeURIComponent(config.pkg.asset)}`;
      download.hidden = false;
    }
  });

  document.querySelectorAll('[data-platform-download]').forEach(link => {
    const asset = config.downloads?.[link.dataset.platformDownload];
    if (repository && asset) { link.href = `${repository}/releases/download/v${encodeURIComponent(config.version)}/${encodeURIComponent(asset)}`; link.hidden = false; }
  });

  const tabs = [...document.querySelectorAll('[role="tab"]')];
  function selectTab(tab, focus) {
    tabs.forEach(item => {
      const selected = item === tab;
      item.setAttribute('aria-selected', String(selected));
      item.tabIndex = selected ? 0 : -1;
      document.getElementById(item.getAttribute('aria-controls')).hidden = !selected;
    });
    if (focus) tab.focus();
  }
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => selectTab(tab, false));
    tab.addEventListener('keydown', event => {
      let target;
      if (event.key === 'ArrowRight') target = (index + 1) % tabs.length;
      if (event.key === 'ArrowLeft') target = (index + tabs.length - 1) % tabs.length;
      if (event.key === 'Home') target = 0;
      if (event.key === 'End') target = tabs.length - 1;
      if (target !== undefined) { event.preventDefault(); selectTab(tabs[target], true); }
    });
  });

  let statusTimeout;
  function announce(message) {
    const status = document.getElementById('copy-status');
    clearTimeout(statusTimeout);
    status.textContent = message;
    statusTimeout = setTimeout(() => { status.textContent = ''; }, 3500);
  }
  async function copyText(text) {
    if (navigator.clipboard && window.isSecureContext) {
      try { await navigator.clipboard.writeText(text); return true; } catch (_) { /* Try the selection fallback. */ }
    }
    const previous = document.activeElement;
    const textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.setAttribute('aria-label', '복사할 명령');
    textarea.style.cssText = 'position:fixed;left:-9999px;top:0;';
    document.body.appendChild(textarea);
    textarea.select();
    let copied = false;
    try { copied = document.execCommand('copy'); } catch (_) { copied = false; }
    textarea.remove();
    previous?.focus();
    return copied;
  }
  document.querySelectorAll('[data-copy]').forEach(button => {
    button.addEventListener('click', async () => {
      const text = document.getElementById(button.dataset.copy)?.textContent;
      if (!text) return;
      const copied = await copyText(text);
      announce(copied ? '클립보드에 복사했습니다.' : '자동으로 복사할 수 없습니다. 명령을 선택해 복사하세요.');
    });
  });

  document.querySelectorAll('.screenshot-frame img').forEach(img => {
    const fallback = () => {
      img.hidden = true;
      const message = img.parentElement.querySelector('.screenshot-fallback');
      if (message) message.hidden = false;
    };
    img.addEventListener('error', fallback);
    if (img.complete && img.naturalWidth === 0) fallback();
  });
})();
