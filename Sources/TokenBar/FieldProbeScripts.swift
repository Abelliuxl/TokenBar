import Foundation

public enum FieldProbeScripts {
    public static let enableCaptureAtDocumentStart = "window.__tokenBarCaptureEnabled = true;"

    public static let networkCapture = """
    (function() {
      if (window.__tokenBarNetworkHookInstalled) return;
      window.__tokenBarNetworkHookInstalled = true;
      window.__tokenBarCaptureEnabled = false;
      const post = (payload) => {
        if (!window.__tokenBarCaptureEnabled) return;
        try { window.webkit.messageHandlers.tokenBarFieldProbe.postMessage(payload); } catch (_) {}
      };
      const originalFetch = window.fetch;
      if (originalFetch) {
        window.fetch = function(input, init) {
          const request = new Request(input, init);
          const requestBody = init && typeof init.body === 'string' ? init.body.slice(0, 12000) : null;
          return originalFetch.apply(this, arguments).then((response) => {
            try {
              const clone = response.clone();
              clone.text().then((body) => {
                if (body && (body.trim().startsWith('{') || body.trim().startsWith('['))) {
                  post({ type: 'network', url: request.url, method: request.method || 'GET', body: body.slice(0, 240000), requestBody: requestBody });
                }
              }).catch(() => {});
            } catch (_) {}
            return response;
          });
        };
      }
      const originalOpen = XMLHttpRequest.prototype.open;
      const originalSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function(method, url) {
        this.__tokenBarMethod = method || 'GET';
        this.__tokenBarURL = String(url || '');
        return originalOpen.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function(body) {
        this.addEventListener('load', function() {
          try {
            const responseBody = this.responseType === 'json' ? JSON.stringify(this.response || {}) : (this.responseText || '');
            if (responseBody && (responseBody.trim().startsWith('{') || responseBody.trim().startsWith('['))) {
              post({ type: 'network', url: this.__tokenBarURL || location.href, method: this.__tokenBarMethod || 'GET', body: responseBody.slice(0, 240000), requestBody: typeof body === 'string' ? body.slice(0, 12000) : null });
            }
          } catch (_) {}
        });
        return originalSend.apply(this, arguments);
      };
    })();
    """

    public static let startSelection = """
    (function() {
      if (window.__tokenBarFieldMode) return true;
      window.__tokenBarCaptureEnabled = true;
      window.__tokenBarFieldMode = true;
      const semantic = /(balance|quota|credit|remaining|available|wallet|usage|limit|token|credits|余额|额度|剩余|可用|用量|积分|次数)/i;
      const money = /(¥|￥|\\$|€|元|CNY|RMB|USD|tokens?|credits?|%)/i;
      const clean = (value) => String(value || '').replace(/\\s+/g, ' ').trim();
      const quote = (value) => String(value).replace(/\\\\/g, '\\\\\\\\').replace(/"/g, '\\\\"');
      const unique = (selector) => { try { return document.querySelectorAll(selector).length === 1; } catch (_) { return false; } };
      const cssPath = (el) => {
        if (!el || el.nodeType !== 1) return 'body';
        if (el.id && unique('#' + CSS.escape(el.id))) return '#' + CSS.escape(el.id);
        for (const attr of ['data-testid', 'data-slot', 'aria-label', 'name']) {
          const value = el.getAttribute(attr);
          if (value) {
            const selector = el.tagName.toLowerCase() + '[' + attr + '="' + quote(value) + '"]';
            if (unique(selector)) return selector;
          }
        }
        const parts = [];
        let current = el;
        while (current && current.nodeType === 1 && current !== document.body && parts.length < 6) {
          let part = current.tagName.toLowerCase();
          const classes = Array.from(current.classList || []).filter((value) => value.length < 40 && !/^css-|^sc-/.test(value)).slice(0, 2);
          if (classes.length) part += '.' + classes.map((value) => CSS.escape(value)).join('.');
          const siblings = current.parentElement ? Array.from(current.parentElement.children).filter((node) => node.tagName === current.tagName) : [];
          if (siblings.length > 1) part += ':nth-of-type(' + (siblings.indexOf(current) + 1) + ')';
          parts.unshift(part);
          current = current.parentElement;
        }
        return parts.length ? parts.join(' > ') : 'body';
      };
      const valueKind = (text) => /%/.test(text) ? 'percent' : (/[0-9][^\\n]{0,12}\\/[ ]*[0-9]/.test(text) ? 'usedTotal' : 'balance');
      const unit = (text) => text.match(/%|¥|￥|\\$|€|元|CNY|RMB|USD|tokens?|credits?/i)?.[0] || '';
      const makeCandidate = (el, selectedText, distance) => {
        const text = clean(el.innerText || el.textContent);
        if (!text || text.length > 700 || !text.includes(selectedText)) return null;
        const attrs = [el.id, el.getAttribute('aria-label'), el.getAttribute('data-testid'), el.getAttribute('data-slot'), el.className].filter(Boolean).join(' ');
        let score = 60 - distance * 8;
        if (text === selectedText) score += 35;
        if (semantic.test(text + ' ' + attrs)) score += 32;
        if (money.test(text)) score += 18;
        return { source: 'dom', label: clean(el.getAttribute('aria-label') || el.getAttribute('data-slot') || ''), preview: text, score: score, selector: cssPath(el), valueKind: valueKind(text), unit: unit(text) };
      };
      const emitSelection = () => {
        const selection = window.getSelection();
        const selectedText = clean(selection && selection.toString());
        if (!selectedText || !selection.rangeCount) return;
        let node = selection.getRangeAt(0).commonAncestorContainer;
        if (node.nodeType !== 1) node = node.parentElement;
        const candidates = [];
        let current = node;
        for (let distance = 0; current && distance < 5; distance += 1, current = current.parentElement) {
          const candidate = makeCandidate(current, selectedText, distance);
          if (candidate) candidates.push(candidate);
        }
        const seen = new Set();
        const uniqueCandidates = candidates.filter((candidate) => !seen.has(candidate.selector) && seen.add(candidate.selector));
        window.webkit.messageHandlers.tokenBarFieldSelection.postMessage(JSON.stringify({ type: 'selection', text: selectedText, candidates: uniqueCandidates }));
      };
      window.__tokenBarStopFieldSelection = () => {
        document.removeEventListener('mouseup', emitSelection, true);
        window.__tokenBarFieldMode = false;
      };
      document.addEventListener('mouseup', emitSelection, true);
      return true;
    })()
    """

    public static let stopSelection = """
    (function() { if (window.__tokenBarStopFieldSelection) window.__tokenBarStopFieldSelection(); window.__tokenBarCaptureEnabled = false; return true; })()
    """
}
