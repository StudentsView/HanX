'use strict';
const {warningSummary}=require('./model.js');

function text(value,limit=12000){
 const plain=String(value??'').replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g,'').trim();
 return plain.length>limit?plain.slice(0,limit)+'…':plain;
}
const help=Object.freeze({
 document:['문서 편집','문단을 선택해 리본에서 글자 모양과 정렬을 바꿀 수 있습니다. 표의 일반 셀은 두 번 눌러 편집하세요. 그림이나 필드가 포함된 내용은 원본을 보존합니다.'],
 spreadsheet:['도표 편집','셀에는 계산 결과가 표시됩니다. 수식 입력줄에서 원래 값과 수식을 편집하세요. 셀을 두 번 누르거나 F2를 눌러 직접 편집할 수 있습니다.'],
 presentation:['슬라이드 편집','도형을 끌어서 이동하고 모서리로 크기를 조절합니다. 위쪽 원은 회전 손잡이입니다. 텍스트는 두 번 눌러 편집하세요.']
});
class NoticeCenter {
 constructor(show){this.show=show;this.tail=Promise.resolve();this.reset();}
 reset(){this.seen=new Set();}
 enqueue(work){const result=this.tail.then(work);this.tail=result.catch(()=>{});return result;}
 warnings(warnings){
  const values=[...new Set((Array.isArray(warnings)?warnings:[]).filter(w=>typeof w==='string').map(w=>text(w,2000)).filter(Boolean))];
  const seen=this.seen;
  return this.enqueue(async()=>{
   const fresh=values.filter(w=>!seen.has(w));if(!fresh.length)return;
   const summary=[...new Set(fresh.map(w=>warningSummary([w])))].join('\n\n');
   const choice=await this.show({type:'warning',title:'HanX',message:'문서 호환성 확인',detail:summary,buttons:['확인','자세히'],defaultId:0,cancelId:0});
   if(choice.response===1)await this.show({type:'warning',title:'HanX',message:'호환성 상세 정보',detail:text(fresh.join('\n\n')),buttons:['닫기'],defaultId:0,cancelId:0});
   for(const warning of fresh)seen.add(warning);
  });
 }
 error(error){return this.enqueue(()=>this.show({type:'error',title:'HanX',message:'작업을 완료하지 못했습니다.',detail:text(error?.message||error||'다시 시도하세요.'),buttons:['확인'],defaultId:0,cancelId:0}));}
 help(topic){
  if(!Object.hasOwn(help,topic))return Promise.reject(Error('지원하지 않는 도움말입니다.'));
  const [message,detail]=help[topic];
  return this.enqueue(()=>this.show({type:'info',title:'HanX',message,detail,buttons:['확인'],defaultId:0,cancelId:0}));
 }
}
module.exports={NoticeCenter};
