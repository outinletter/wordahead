const path = require('path');
const {execFileSync} = require('child_process');
execFileSync('python3', [path.join(__dirname, 'update_translations.py')], {stdio: 'inherit'});
