(function(root){
 function paragraphText(p){return (p?.inlines||[]).map(i=>i.text?i.text._0:i.tab?'\t':i.lineBreak?'\n':i.field?i.field._0?.display||'':'').join('');}
 function blockText(block){return block.paragraph?paragraphText(block.paragraph._0):block.table?block.table._0.rows.map(row=>row.map(cell=>cell.blocks.map(blockText).join('\n')).join('\t')).join('\n'):'';}
 function columnName(index){let result='';for(let n=index+1;n>0;n=Math.floor((n-1)/26))result=String.fromCharCode(65+(n-1)%26)+result;return result;}
 function color(c,fallback='#ffffff'){return c?'#'+['r','g','b'].map(k=>Math.max(0,Math.min(255,Math.round(c[k]))).toString(16).padStart(2,'0')).join(''):fallback;}
 function imageSource(image){const ext=image?.name?.split('.').pop().toLowerCase(),mime={png:'image/png',jpg:'image/jpeg',jpeg:'image/jpeg',gif:'image/gif',webp:'image/webp'}[ext];return mime&&typeof image.data==='string'&&/^[A-Za-z0-9+/=\r\n]+$/.test(image.data)?`data:${mime};base64,${image.data}`:null;}
 function runStyle(c={}){return {fontFamily:c.fontName?JSON.stringify(c.fontName)+', serif':'serif',fontSize:Math.max(1,Math.min(400,c.size||10))+'pt',fontWeight:c.bold?'700':'400',fontStyle:c.italic?'italic':'normal',color:color(c.color,'#172e45'),backgroundColor:color(c.highlight,'transparent'),textDecoration:[c.underline&&c.underline!=='none'?'underline':'',c.strike?'line-through':''].filter(Boolean).join(' '),verticalAlign:c.verticalAlign==='superscript'?'super':c.verticalAlign==='subscript'?'sub':'baseline'};}
 const api={imageSource,runStyle,paragraphText,blockText,columnName,color};if(typeof module!=='undefined')module.exports=api;else root.HanXModel=api;
})(typeof window!=='undefined'?window:globalThis);
