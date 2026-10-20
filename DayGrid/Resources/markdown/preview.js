// 본문 미리보기. 앱이 `renderMarkdown(source)`를 부르면 마크다운을 HTML로 바꾸고,
// DOMPurify로 스크립트와 위험한 속성을 걸러 낸 뒤 #content에 넣는다.
// 읽기 화면은 이어서 `enableTaskToggles()`를 불러 체크리스트를 누를 수 있게 한다.
(function () {
  'use strict';

  // "- [ ] 할일", "- [x] 끝낸 일"을 체크박스로 바꾼다. 체크박스에는 문서 순서대로 0, 1, 2…를 붙인다.
  // 앱(Core MarkdownTaskList)이 같은 순서로 원문의 체크를 찾으므로, 규칙을 바꾸면 양쪽을 같이 바꾼다.
  function taskLists(md) {
    md.core.ruler.after('inline', 'task_lists', function (state) {
      var tokens = state.tokens;
      var taskIndex = 0;
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
        checkbox.content = '<input type="checkbox" class="task-checkbox" data-task-index="' + taskIndex + '" disabled' +
          (match[1] === ' ' ? '' : ' checked') + '> ';
        taskIndex += 1;
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

  // 체크박스를 누를 수 있게 하고, 누르면 그 순서를 앱에 보낸다. 앱이 원문을 고쳐 다시 그린다.
  window.enableTaskToggles = function () {
    var handlers = window.webkit && window.webkit.messageHandlers;
    if (!handlers || !handlers.taskToggle) {
      return false;
    }
    var boxes = document.querySelectorAll('#content input.task-checkbox');
    Array.prototype.forEach.call(boxes, function (box) {
      box.disabled = false;
      box.addEventListener('click', function () {
        handlers.taskToggle.postMessage(Number(box.getAttribute('data-task-index')));
      });
    });
    return true;
  };
})();
