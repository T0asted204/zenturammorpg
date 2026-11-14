// npm install --no-save playwright (from repository root)
// Run a server on :9080 and serve build/web on :8060 first.
// TEST_SAVE_FILE=/absolute/server-save.json node tools/browser_smoke.cjs
// CHROME_PATH can override the local Chromium executable.
const {chromium} = require('playwright');
const fs = require('node:fs');
const assert = require('node:assert/strict');
(async () => {
 const browser = await chromium.launch({executablePath:process.env.CHROME_PATH || '/usr/bin/google-chrome',headless:true,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 try {
  const errors=[]; const pages=[]; const names=[]; let frames=0;
  for(let i=0;i<2;i++) {
   const context=await browser.newContext({viewport:{width:1280,height:800},deviceScaleFactor:0.5});
   const page=await context.newPage(); pages.push(page);
   page.on('pageerror',e=>errors.push(e.message));
   page.on('console',m=>{if(m.type()==='error') errors.push(m.text());});
   page.on('websocket',ws=>ws.on('framereceived',()=>frames++));
   await page.goto(process.env.GAME_URL || 'http://127.0.0.1:8060');
   await page.waitForTimeout(10000);
   // Wait for an actual composed canvas frame before sending native input.
   await page.screenshot({timeout:120000});
   const name='web'+String(Date.now()).slice(-8)+i; names.push(name);
   await page.mouse.click(500,332); await page.waitForTimeout(500); await page.keyboard.press('Control+a'); await page.keyboard.type(name,{delay:200});
   await page.mouse.click(500,373); await page.waitForTimeout(500); await page.keyboard.type('browser-test-pass',{delay:200}); await page.waitForTimeout(500);
   await page.mouse.click(600,453); await page.waitForTimeout(2000);
   await page.screenshot({path:require('node:path').join(__dirname,`../build/browser-client-${i}.png`)});
  }
  assert(frames>10,'Both browser clients should receive live WebSocket snapshots');
  await pages[0].mouse.click(700,560); // focus world, then exercise movement
  await pages[0].keyboard.down('d'); await pages[0].waitForTimeout(1200); await pages[0].keyboard.up('d');
  await pages[0].waitForTimeout(6000);
  await pages[0].screenshot({path:process.env.SCREENSHOT || require('node:path').join(__dirname,'../build/browser-gameplay.png')});
  if(process.env.TEST_SAVE_FILE) {
   const data=JSON.parse(fs.readFileSync(process.env.TEST_SAVE_FILE,'utf8'));
   for(const name of names) assert(data.accounts[name],`Persisted browser account ${name}`);
   assert(Math.abs(data.accounts[names[0]].x)>1,'Browser movement reached authoritative save');
  }
  assert.deepEqual(errors,[],'Browser must have no script/WebGL errors');
  console.log('BROWSER_SMOKE_PASS', {names,frames});
 } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
