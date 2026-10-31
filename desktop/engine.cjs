const {spawn} = require('node:child_process');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const ALLOWED = new Set(['replace_text','append_paragraph','append_block','insert_block','delete_block','set_paragraph','style_paragraph','set_cell','set_page','add_slide','duplicate_slide','delete_slide','move_slide','set_notes','set_transition','add_shape','update_shape','delete_shape','set_range','fill_formula','style_range','clear_range','add_sheet','delete_sheet','merge','unmerge','freeze','set_column_width','set_row_height','define_name']);
function validateOperations(ops) {
  if (!Array.isArray(ops) || !ops.length || ops.length > 10000) throw Error('Expected 1–10000 editing operations.');
  if (JSON.stringify(ops).length > 8e6) throw Error('This edit is too large.');
  for (const op of ops) {
    if (!op || typeof op !== 'object' || !ALLOWED.has(op.op)) throw Error('Unsupported editing operation.');
    const visit=(value,depth=0)=>{if(depth>30)throw Error('This edit is too deeply nested.');if(typeof value==='number'&&!Number.isFinite(value))throw Error('Invalid numeric value.');if(value&&typeof value==='object')for(const [key,item] of Object.entries(value)){if(['imagePath','path','__proto__','constructor','prototype'].includes(key))throw Error('File paths are not allowed in editing operations.');visit(item,depth+1);}};visit(op);
  }
  return ops;
}
function engineCandidates({resourcesPath, appPath, packaged, platform = process.platform, env = process.env}) {
  const exe = platform === 'win32' ? 'hanx.exe' : 'hanx';
  const bundled = [path.join(resourcesPath,'cli',exe),path.join(resourcesPath,exe)];
  // Overrides are a development facility. Packaged apps always use their bundled engine.
  return packaged ? bundled : [env.HANX_CLI_PATH, ...bundled, path.resolve(appPath,'../build/hanx-cli'),path.resolve(appPath,'../build/platform/cli',exe)].filter(Boolean);
}
async function resolveEngine(options) {
  for (const candidate of engineCandidates(options)) {
    if (!path.isAbsolute(candidate)) continue;
    try { await fs.access(candidate); return candidate; } catch {}
  }
  throw Error('The HanX engine is missing. Install a complete HanX package, or set HANX_CLI_PATH for development.');
}
function runEngine(executable,args,input) {
  return new Promise((resolve,reject) => {
    const child=spawn(executable,args,{shell:false,windowsHide:true,stdio:['pipe','pipe','pipe']});
    child.stdout.setEncoding('utf8');child.stderr.setEncoding('utf8');
    let stdout='',stderr='',finished=false;
    const timer=setTimeout(()=>{child.kill(); reject(Error('The HanX engine took too long.'));},120000);
    function finish(error,data){if(finished)return; finished=true;clearTimeout(timer);error?reject(error):resolve(data);}
    child.on('error',e=>finish(e));
    child.stdout.on('data',data=>{stdout+=data;if(stdout.length>128e6){child.kill();finish(Error('This file exceeds the editor’s size limit.'));}});
    child.stderr.on('data',data=>{if(stderr.length<32000)stderr+=data;});
    child.on('close',code=>{try{const envelope=JSON.parse(stdout);if(!envelope.ok)throw Error(envelope.error?.message || 'The engine could not process this file.');if(code!==0)throw Error(stderr || `Engine exited with ${code}`);finish(null,envelope.data);}catch(e){finish(Error(e.message+(stderr?'\n'+stderr:'')));}});
    child.stdin.on('error',()=>{});child.stdin.end(input===undefined ? undefined : JSON.stringify(input));
  });
}
const defaults={document:{kind:'document',blocks:[{text:''}]},spreadsheet:{kind:'spreadsheet',sheets:[{name:'Sheet1',rows:[['']]}]},presentation:{kind:'presentation',slides:[{title:'제목을 입력하세요',body:['내용을 입력하세요']}]}};
const formats={document:['docx','hwpx','hwp','hml','txt','md','json','pdf'],spreadsheet:['xlsx','csv','tsv','json','pdf'],presentation:['pptx','json','pdf']};
class Session {
  constructor(executable){this.executable=executable;this.file=null;this.source=null;this.dirty=false;this.history=[];this.future=[];this.counter=0;}
  async init(){this.directory=await fs.mkdtemp(path.join(os.tmpdir(),'hanx-desktop-'));return this;}
  async next(){return path.join(this.directory,`${++this.counter}.json`);}
  async read(){const data=await runEngine(this.executable,['read',this.file]);if(data.kind==='spreadsheet'){data.calculated=[];for(let i=0;i<data.model.sheets.length;i++){const sheet=await runEngine(this.executable,['spreadsheet','read',this.file,'--sheet',data.model.sheets[i].name]);data.calculated.push(Object.fromEntries(sheet.cells.map(c=>[c.address,c])));}}return {...data,path:this.source,dirty:this.dirty,canUndo:!!this.history.length,canRedo:!!this.future.length};}
  async open(source){const data=await runEngine(this.executable,['read',source]);if(!formats[data.kind])throw Error('Open a document, spreadsheet, or presentation.');const target=await this.next();await runEngine(this.executable,['create','--spec','-','--output',target],{kind:data.kind,model:data.model});this.file=target;this.source=source;this.dirty=false;this.kind=data.kind;this.history=[];this.future=[];return this.read();}
  async create(kind){if(!defaults[kind])throw Error('Unknown file type.');const target=await this.next();await runEngine(this.executable,['create','--spec','-','--output',target],defaults[kind]);this.file=target;this.source=null;this.kind=kind;this.dirty=false;this.history=[];this.future=[];return this.read();}
  async edit(ops){
    validateOperations(ops);if(!this.file)throw Error('먼저 파일을 열거나 새로 만드세요.');
    let current=this.file;
    const batches=ops.some(op=>op.op==='set_paragraph')?ops.map(op=>[op]):[ops];
    for(const batch of batches){
      const op=batch[0];let original;
      if(batch.length===1&&op.op==='set_paragraph'){
        const before=await runEngine(this.executable,['read',current]);original=before.model.sections?.[op.section||0]?.blocks?.[op.block]?.paragraph?._0;
        if(original?.inlines.some(i=>i.image||i.field||i.pageBreak))throw Error('그림 또는 필드가 포함된 문단은 읽기 전용입니다.');
      }
      const target=await this.next();await runEngine(this.executable,['edit',current,'--ops','-','--output',target],batch);
      if(original){const after=await runEngine(this.executable,['read',target]),paragraph=after.model.sections[op.section||0].blocks[op.block].paragraph._0;paragraph.props={...original.props,...(op.alignment?{alignment:op.alignment}:{}),...(op.styleName!==undefined?{styleName:op.styleName}:{})};await runEngine(this.executable,['create','--spec','-','--output',target,'--force'],{kind:after.kind,model:after.model});}
      current=target;
    }
    this.history.push(this.file);this.future=[];this.file=current;this.dirty=true;return this.read();
  }
  async copySlide(index){const data=await this.read();if(data.kind!=='presentation'||!Number.isInteger(index)||!data.model.slides[index])throw Error('슬라이드를 선택하세요.');this.clipboard={slide:structuredClone(data.model.slides[index]),images:structuredClone(data.model.images)};return true;}
  async pasteSlide(index){if(!this.clipboard||this.kind!=='presentation')throw Error('복사한 슬라이드가 없습니다.');const data=await this.read();if(!Number.isInteger(index)||index<0||index>data.model.slides.length)throw Error('Invalid slide index.');data.model.slides.splice(index,0,structuredClone(this.clipboard.slide));Object.assign(data.model.images,this.clipboard.images);const target=await this.next();await runEngine(this.executable,['create','--spec','-','--output',target],{kind:'presentation',model:data.model});this.history.push(this.file);this.future=[];this.file=target;this.dirty=true;return this.read();}
  async undo(redo=false){const from=redo?this.future:this.history,to=redo?this.history:this.future;if(from.length){to.push(this.file);this.file=from.pop();this.dirty=true;}return this.read();}
  async save(destination){if(!this.file)throw Error('Open or create a file first.');const ext=path.extname(destination).slice(1).toLowerCase();if(!formats[this.kind].includes(ext))throw Error(`Choose a supported ${this.kind} format.`);const result=await runEngine(this.executable,['convert',this.file,'--output',destination,'--force']);if(ext!=='pdf'){this.source=destination;this.dirty=false;}return {...await this.read(),saveWarnings:result.warnings||[],exported:ext==='pdf'};}
  async close(){if(this.directory)await fs.rm(this.directory,{recursive:true,force:true});}
}
module.exports={validateOperations,engineCandidates,resolveEngine,runEngine,Session,formats};
