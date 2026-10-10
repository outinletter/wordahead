const WordAheadDictionary = {
  shards:new Map(), pending:new Map(),
  install(id,entries) {this.shards.delete(id);this.shards.set(id,entries);while(this.shards.size>8)this.shards.delete(this.shards.keys().next().value);},
  async lookup(word) {
    const key = word.toLowerCase();
    const hash = new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(key)));
    const id = hash[0].toString(16).padStart(2,'0');
    if (!this.shards.has(id)) {
      if (!this.pending.has(id)) this.pending.set(id,new Promise((resolve,reject) => {
        const script=document.createElement('script');script.src=`dictionary/${id}.js?v=20261008`;
        script.onload=()=>{resolve(this.shards.get(id));this.pending.delete(id);script.remove();};
        script.onerror=()=>{this.pending.delete(id);script.remove();reject(new Error('내장 사전을 불러올 수 없습니다.'));};
        document.head.append(script);
      }));
      const entries=await this.pending.get(id);return entries&&Object.hasOwn(entries,key)?entries[key]:null;
    }
    const entries=this.shards.get(id);return Object.hasOwn(entries,key)?entries[key]:null;
  },
  async preferred(raw,key) {
    raw=raw.toLowerCase().replaceAll('’',"'");
    const exact=await this.lookup(raw);
    if(exact?.[3]==='ko')return {entry:exact,word:raw};
    const forms=new Set([key,...Array.from((exact?.[2]||'').matchAll(/(?:plural|participle|tense|comparative|superlative|form)[^.;]*?\bof\s+([A-Za-z]+(?:['-][A-Za-z]+)*)/g),x=>x[1].toLowerCase())]);
    let fallback=null;
    for(const word of forms){if(word===raw)continue;const entry=await this.lookup(word);if(entry?.[3]==='ko')return {entry,word};if(entry&&!fallback)fallback={entry,word};}
    return exact?{entry:exact,word:raw}:fallback;
  },
  async show(raw,key) {
    const selection=currentWord;
    try {
      const result=await this.preferred(raw,key);
      if(currentWord!==selection)return;
      if(!result){if(!selection.entry?.[2])$('#sheet-meaning').textContent='내장 사전에 수록되지 않은 단어입니다.';return;}
      const {entry,word}=result;
      selection.entry=entry;
      $('#sheet-part').textContent=entry[1];$('#sheet-phonetic').textContent=entry[0]||'';
      $('#sheet-meaning').textContent=entry[2];
      $('#dictionary-source').href=`https://${entry[3]==='ko'?'ko':'en'}.wiktionary.org/wiki/`+encodeURIComponent(word);
      $('#dictionary-source').textContent=`Wiktionary 원문 · ${word}`;$('#dictionary-source').hidden=false;
      const existing=saved.find(x=>x.word===key);
      if(existing){existing.definition=entry[2];existing.phonetic=entry[0];existing.part=entry[1];persist();}
    }catch{if(currentWord===selection&&!DICTIONARY[key])$('#sheet-meaning').textContent='내장 사전을 불러올 수 없습니다.';}
  }
};
