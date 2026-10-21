#!/usr/bin/env node
// Idempotently applies the balanced-brace fallback tool parser to pi's OpenAI completions provider.
// This allows models like Qwen 2.5 Coder (which emit markdown JSON tool calls in text delta)
// to have their tool invocations properly recognized by the Pi harness.

const fs = require('fs');
const path = require('path');

const targetFiles = [
  path.join(__dirname, '..', 'node_modules/@earendil-works/pi-coding-agent/dist/bundle/chunks/openai-completions-OSRCWAAA.js'),
  path.join(__dirname, '..', 'node_modules/@earendil-works/pi-ai/dist/api/openai-completions.js')
];

const fallbackCode = `if(!blocks.some(b=>b.type==="toolCall")){for(let block of blocks){if(block.type==="text"&&block.text){let depth=0,start=-1,inStr=!1,esc=!1,found=[];for(let i=0;i<block.text.length;i++){let ch=block.text[i];if(esc){esc=!1;continue}if(ch==="\\\\"){esc=!0;continue}if(ch==='"'){inStr=!inStr;continue}if(!inStr){if(ch==="{")depth===0&&(start=i),depth++;else if(ch==="}"){depth--;if(depth===0&&start!==-1){let raw=block.text.slice(start,i+1);try{let p=JSON.parse(raw);p&&(p.name||p.tool)&&["read","write","edit","bash"].includes(p.name||p.tool)&&found.push({name:p.name||p.tool,args:p.arguments||p.parameters||p.args||{},raw})}catch(e){}start=-1}}}}if(found.length>0){let cIdx=0;for(let f of found){let callId=\`call_\${Date.now()}_\${cIdx++}_\${Math.random().toString(36).substring(2,7)}\`,toolBlock={type:"toolCall",id:callId,name:f.name,arguments:f.args,partialArgs:JSON.stringify(f.args)};blocks.push(toolBlock),stream2.push({type:"toolcall_start",contentIndex:getContentIndex(toolBlock),partial:output}),block.text=block.text.replace(f.raw,"").replace(/\`\`\`(?:json)?|\`\`\`|<\\/?(?:function-calls|tool_call|tools)>/gi,"").trim()}output.stopReason="toolUse"}}}}for(let block of blocks)finishBlock(block);`;

for (const filePath of targetFiles) {
  if (!fs.existsSync(filePath)) {
    console.warn(`[patch] File not found: ${filePath}`);
    continue;
  }

  let content = fs.readFileSync(filePath, 'utf8');
  if (content.includes('let depth=0,start=-1,inStr=!1,esc=!1,found=[];')) {
    console.log(`[patch] Already patched: ${filePath}`);
    continue;
  }

  // Look for the standard finishBlock loop right before stream error handling
  const standardPattern = /for\(let block of blocks\)finishBlock\(block\);/;
  if (standardPattern.test(content)) {
    content = content.replace(standardPattern, fallbackCode);
    fs.writeFileSync(filePath, content, 'utf8');
    console.log(`[patch] Successfully patched: ${filePath}`);
  } else {
    console.warn(`[patch] Target pattern not found in: ${filePath}`);
  }
}
