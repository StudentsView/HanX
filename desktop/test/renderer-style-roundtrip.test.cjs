const {test}=require('node:test');
const assert=require('node:assert/strict');
const path=require('node:path');
const {Session}=require('../engine.cjs');
const executable=process.env.HANX_CLI_PATH||path.resolve(__dirname,'../../build/hanx-cli');
test('document ribbon font face survives a DOCX session round trip',async()=>{
 const session=await new Session(executable).init();try{
  await session.create('document');await session.edit([{op:'set_paragraph',section:0,block:0,text:'글꼴 확인'},{op:'style_paragraph',section:0,block:0,style:{font:'Arial'}}]);
  const output=path.join(session.directory,'font.docx');await session.save(output);await session.open(output);
  const paragraph=(await session.read()).model.sections[0].blocks[0].paragraph._0;
  assert.equal(paragraph.markProps.fontName,'Arial');assert.equal(paragraph.inlines[0].text._1.fontName,'Arial');
 }finally{await session.close();}
});
test('spreadsheet ribbon font and colors survive an XLSX session round trip',async()=>{
 const session=await new Session(executable).init();try{
  await session.create('spreadsheet');await session.edit([{op:'set_range',sheet:0,start:'A1',values:[['왼쪽','오른쪽']]},{op:'style_range',sheet:0,range:'A1:B1',style:{fontName:'Arial',fontSize:18,italic:true,underline:true,align:'center',color:'123456',fill:'E7EFFA'}}]);
  const output=path.join(session.directory,'font.xlsx');await session.save(output);await session.open(output);
  const cells=(await session.read()).model.sheets[0].cells;
  for(const address of ['A1','B1']){const style=cells[address].style;for(const [key,value] of Object.entries({fontName:'Arial',fontSize:18,italic:true,underline:true,align:'center',color:'123456',fill:'E7EFFA'}))assert.equal(style[key],value,address+' '+key);}
 }finally{await session.close();}
});
