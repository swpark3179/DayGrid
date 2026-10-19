// 본문 미리보기. 앱이 `renderMarkdown(source)`를 부르면 마크다운을 HTML로 바꾸고,
// DOMPurify로 스크립트와 위험한 속성을 걸러 낸 뒤 #content에 넣는다.
(function () {
  'use strict';

  // "- [ ] 할일", "- [x] 끝낸 일"을 체크박스로 바꾼다.
  function taskLists(md) {
    md.core.ruler.after('inline', 'task_lists', function (state) {
      var tokens = state.tokens;
      for (var i = 2; i < tokens.length; i++) {
        var inline = tokens[i];
        if (inline.type !== 'inline' || tokens[i - 1].type !== 'paragraph_open' || tokens[i - 2].type !== 'list_item_open') {
          continue;
        }
        var match = /^\[([ xX])\][  ]/.exec(inline.content);
        var first = inline.children && inline.children[0];
        if (!match || !first || first.type !== 'text' || first.content.indexOf(match[0]) !== 0) {
          continue;
        }
        first.content = first.content.slice(match[0].length);
        var checkbox = new state.Token('html_inline', '', 0);
        checkbox.content = '<input type="checkbox" disabled' + (match[1] === ' ' ? '' : ' checked') + '> ';
        inline.children.unshift(checkbox);
        tokens[i - 2].attrJoin('class', 'task-list-item');
      }
    });
  }

  var md = window.markdownit({ html: true, linkify: true, breaks: true });
  md.use(taskLists);

  window.renderMarkdown = function (source) {
    var html = md.render(String(source || ''));
    document.getElementById('content').innerHTML = window.DOMPurify.sanitize(html);
    return true;
  };
})();
