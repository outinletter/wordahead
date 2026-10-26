const fs=require('fs'),vm=require('vm'),assert=require('assert');
const source=fs.readFileSync('app.js','utf8');let measured=0,created=0;
const context={document:{querySelector:()=>({clientWidth:100}),createElement(tag){assert.equal(tag,'canvas');created++;return{getContext:()=>({measureText(word){measured++;return{width:word.length*10};}})}}},getComputedStyle:()=>({fontWeight:'500',fontSize:'20px',fontFamily:'system-ui'})};
vm.createContext(context);vm.runInContext(source.slice(source.indexOf('function captionBlockMeasure'),source.indexOf('function captionSentences')),context);
const measure=context.captionBlockMeasure({});assert(measure.fits(Array(5).fill('abcdefghi').join(' '),null));assert(!measure.fits(Array(6).fill('abcdefghi').join(' '),null));assert(!measure.fits('x'.repeat(50),null));const before=measured;measure.fits('abcdefghi',null);assert.equal(measured,before);assert.equal(created,1);measure.dispose();
console.log('PASS: five-line wrapping, long tokens, cached text widths; no transcript DOM layout during grouping');
