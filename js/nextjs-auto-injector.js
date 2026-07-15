(function() {
  const fs = require('fs');
  const path = require('path');
  
  const START_MARKER = '// ConsoleLog.nvim auto-injection start';
  const END_MARKER = '// ConsoleLog.nvim auto-injection end';
  const WS_PORT = __WS_PORT__;
  const PROJECT_ID = '__PROJECT_ID__';
  
  const CLIENT_FILES = [
    path.join(__dirname, '../../client/index.js'),
    path.join(__dirname, '../../client/app-index.js'),
    path.join(__dirname, '../../esm/client/index.js')
  ];
  
  function needsPatching(filepath) {
    try {
      if (!fs.existsSync(filepath)) return false;
      const content = fs.readFileSync(filepath, 'utf8');
      return !content.includes(START_MARKER) ||
        !content.includes(`window.__CONSOLELOG_WS_PORT = ${WS_PORT};`);
    } catch (err) {
      return false;
    }
  }
  
  function patchFile(filepath) {
    try {
      const backup = filepath + '.bk';
      let content = fs.readFileSync(filepath, 'utf8');
      if (!fs.existsSync(backup) || !content.includes('window.__CONSOLELOG_WS_PORT')) {
        fs.copyFileSync(filepath, backup);
      }
      
      if (content.includes('window.__CONSOLELOG_WS_PORT') && fs.existsSync(backup)) {
        content = fs.readFileSync(backup, 'utf8');
      }
      
      const clientCodePath = path.join(__dirname, '../../../.consolelog-client-inject.js');
      let clientCode = '';
      try {
        clientCode = fs.readFileSync(clientCodePath, 'utf8');
      } catch (err) {
        return false;
      }

      const injection = `${START_MARKER}
if (typeof window !== "undefined") {
  window.__CONSOLELOG_WS_PORT = ${WS_PORT};
  window.__CONSOLELOG_PROJECT_ID = "${PROJECT_ID}";
  window.__CONSOLELOG_FRAMEWORK = "Next.js";
  window.__CONSOLELOG_DEBUG = true;
}
${clientCode}
${END_MARKER}
`;
      
      if (content.match(/^['"]use client['"]/m)) {
        content = content.replace(/(["']use client["'][;\s]*\n)/, `$1${injection}\n`);
      } else {
        content = injection + '\n' + content;
      }
      
      fs.writeFileSync(filepath, content, 'utf8');
      return true;
    } catch (err) {
      return false;
    }
  }
  
  CLIENT_FILES.forEach(filepath => {
    if (needsPatching(filepath)) {
      patchFile(filepath);
    }
  });
})();
