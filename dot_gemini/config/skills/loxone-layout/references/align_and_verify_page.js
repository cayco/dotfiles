// Reusable Loxone Config 17.3 Pin-Sorted Attachment Aligner & 8-Gate Page Verifier
// Usage inside `loxone-config` MCP `code_run`: set `PAGE_NAME` (and optional `STANDALONE_IDS` / `ORPHAN_IDS`).

const PAGE_NAME = "Gabinet";
const STANDALONE_IDS = new Set([]); // UUIDs of shared OutputRefs (>=2 local inputs) or cross-page InputRefs
const ORPHAN_IDS = new Set([]);     // UUIDs of unconnected InputRefs or InputRef->OutputRef bridge endpoints

const isOutRefType = (t) => t === "OutputRef" || t === "Memory";
const ps = cfg.get_pages().pages.find(p => p.name === PAGE_NAME);
const PAGE_UUID = ps.uuid;

// 1. Save remote-page referenceMark positions so cross-page reconnections never perturb other pages
const savedRemote = new Map();
for (const other of cfg.get_pages().pages) {
  if (other.uuid === PAGE_UUID) continue;
  const rp = cfg.get_page({ uuid: other.uuid }).page;
  for (const m of (rp.referenceMarks || [])) {
    if (m.placement === "manual" || m.position.y > 0) {
      savedRemote.set(m.uuid, { x: m.position.x, y: m.position.y });
    }
  }
}

// 2. Build visible pin index maps (inputs + parameters for comparators!)
let page = cfg.get_page({ uuid: PAGE_UUID }).page;
const bmap = new Map(page.functionBlocks.map(b => [b.uuid, b]));
const blockPinMeta = new Map();
for (const b of page.functionBlocks) {
  const isStand = STANDALONE_IDS.has(b.uuid);
  if ((b.type === "InputRef" || isOutRefType(b.type) || b.type === "Text" || b.size.width <= 10) && !isStand) continue;
  const det = cfg.get_block({ uuid: b.uuid }).block;
  const visIn = det.connectors.inputs.filter(c => !c.hidden);
  const visParam = det.connectors.parameters.filter(c => !c.hidden);
  const visOut = det.connectors.outputs.filter(c => !c.hidden);
  const inIdx = new Map();
  visIn.forEach((c, i) => inIdx.set(c.key, i));
  visParam.forEach((c, i) => { if (!inIdx.has(c.key)) inIdx.set(c.key, visIn.length + i); });
  const outIdx = new Map(visOut.map((c, i) => [c.key, i]));
  blockPinMeta.set(b.uuid, { b, inIdx, outIdx, baseDy: isStand ? 0 : (b.size.width >= 2000 ? 480 : 288) });
}

// 3. Pre-compute exact pin-sorted (x, y) slots for all InputRefs, OutputRefs/Memory, and referenceMarks
const allConns = cfg.get_connections().connections;
const targetInSlot = new Map(), targetOutSlot = new Map(), remoteRestore = new Map();
for (const c of allConns) {
  if (!c.isReference) continue;
  const eKey = `${c.from.blockUuid}.${c.from.connectorKey}->${c.to.blockUuid}.${c.to.connectorKey}`;
  remoteRestore.set(eKey, {
    inPos: c.referenceInUuid ? savedRemote.get(c.referenceInUuid) : null,
    outPos: c.referenceOutUuid ? savedRemote.get(c.referenceOutUuid) : null,
  });
}

const apiByBlock = new Map();
for (const om of (page.referenceMarks || [])) {
  if (om.side === "output" && om.connectorKey === "OutputAPI") {
    if (!apiByBlock.has(om.blockUuid)) apiByBlock.set(om.blockUuid, new Set());
    apiByBlock.get(om.blockUuid).add(om.position.y);
  }
}

for (const [bu, meta] of blockPinMeta.entries()) {
  const { b, inIdx, outIdx, baseDy } = meta;
  const L = [], R = [];
  const dirInY = new Set(), dirOutY = new Set(apiByBlock.get(bu) || []);
  for (const c of allConns) {
    const eKey = `${c.from.blockUuid}.${c.from.connectorKey}->${c.to.blockUuid}.${c.to.connectorKey}`;
    if (c.to.blockUuid === bu) {
      const fb = bmap.get(c.from.blockUuid);
      if (fb && fb.type === "InputRef" && fb.size.width > 10 && !STANDALONE_IDS.has(fb.uuid) && !ORPHAN_IDS.has(fb.uuid) && !c.isReference) {
        L.push({ isMark: false, uuid: fb.uuid, pIdx: inIdx.get(c.to.connectorKey) ?? 0, title: fb.title });
      } else if (c.isReference) {
        L.push({ isMark: true, eKey, pIdx: inIdx.get(c.to.connectorKey) ?? 0, title: c.from.blockTitle });
      } else if (fb && fb.size.width > 10 && inIdx.has(c.to.connectorKey)) {
        dirInY.add(b.position.y + baseDy + inIdx.get(c.to.connectorKey) * 192);
      }
    }
    if (c.from.blockUuid === bu) {
      const tb = bmap.get(c.to.blockUuid);
      if (tb && isOutRefType(tb.type) && tb.size.width > 10 && !STANDALONE_IDS.has(tb.uuid) && !ORPHAN_IDS.has(tb.uuid) && !c.isReference) {
        R.push({ isMark: false, uuid: tb.uuid, pIdx: outIdx.get(c.from.connectorKey) ?? 0, title: tb.title });
      } else if (c.isReference) {
        R.push({ isMark: true, eKey, pIdx: outIdx.get(c.from.connectorKey) ?? 0, title: c.to.blockTitle });
      } else if (tb && tb.size.width > 10 && outIdx.has(c.from.connectorKey)) {
        dirOutY.add(b.position.y + baseDy + outIdx.get(c.from.connectorKey) * 192);
      }
    }
  }
  L.sort((a, z) => a.pIdx - z.pIdx || (a.isMark ? 1 : 0) - (z.isMark ? 1 : 0) || a.title.localeCompare(z.title));
  R.sort((a, z) => a.pIdx - z.pIdx || (a.isMark ? 1 : 0) - (z.isMark ? 1 : 0) || a.title.localeCompare(z.title));

  let curY = -Infinity;
  const xL = b.position.x - 3072;
  for (const it of L) {
    let y = Math.max(b.position.y + baseDy + it.pIdx * 192, curY + 192);
    while (dirInY.has(y)) y += 192;
    if (!it.isMark) cfg.update_block({ uuid: it.uuid, position: { x: xL, y } });
    else targetInSlot.set(it.eKey, { x: xL, y });
    curY = y;
  }

  const apiYs = [...(apiByBlock.get(bu) || [])];
  const needTight = apiYs.length > 0 && (b.position.y + baseDy + R.length * 192 > Math.min(...apiYs));
  const rStart = needTight ? Math.max(b.position.y + 96, Math.min(...apiYs) - R.length * 192) : (b.position.y + baseDy);
  curY = rStart - 192;
  const xR = b.position.x + b.size.width + 959;
  for (const it of R) {
    let y = needTight ? (curY + 192) : Math.max(rStart + it.pIdx * 192, curY + 192);
    while (dirOutY.has(y)) y += 192;
    if (!it.isMark) cfg.update_block({ uuid: it.uuid, position: { x: xR, y } });
    else targetOutSlot.set(it.eKey, { x: xR, y });
    curY = y;
  }
}

// 4. Reconnect reference:true edges and IMMEDIATELY position live mark handles (preserving inversion & remote marks!)
const refConns = allConns.filter(c => c.isReference && (blockPinMeta.has(c.from.blockUuid) || blockPinMeta.has(c.to.blockUuid)));
for (const c of refConns) {
  const fu = c.from.blockUuid, fk = c.from.connectorKey, tu = c.to.blockUuid, tk = c.to.connectorKey;
  const eKey = `${fu}.${fk}->${tu}.${tk}`;
  const td = cfg.get_block({ uuid: tu }).block;
  const tc = [...td.connectors.inputs, ...td.connectors.parameters].find(x => x.key === tk);
  const wasInv = tc ? !!tc.inverted : false;

  cfg.disconnect_blocks({ from_block_uuid: fu, from_connector_key: fk, to_block_uuid: tu, to_connector_key: tk });
  const res = cfg.connect_blocks({ from_block_uuid: fu, from_connector_key: fk, to_block_uuid: tu, to_connector_key: tk, reference: true });

  const td2 = cfg.get_block({ uuid: tu }).block;
  const tc2 = [...td2.connectors.inputs, ...td2.connectors.parameters].find(x => x.key === tk);
  if (tc2 && !!tc2.inverted !== wasInv) cfg.set_connector_inverted({ block_uuid: tu, connector_key: tk, inverted: wasInv });

  const inSlot = targetInSlot.get(eKey) || remoteRestore.get(eKey)?.inPos;
  const outSlot = targetOutSlot.get(eKey) || remoteRestore.get(eKey)?.outPos;
  if (inSlot && res.connection?.referenceInUuid) cfg.update_block({ uuid: res.connection.referenceInUuid, position: inSlot });
  if (outSlot && res.connection?.referenceOutUuid) cfg.update_block({ uuid: res.connection.referenceOutUuid, position: outSlot });
}

// 5. Verify all geometry gates == 0
const finalPage = cfg.get_page({ uuid: PAGE_UUID }).page;
const pb = finalPage.bounds;
const realBlocks = finalPage.functionBlocks.filter(b => b.size.width > 10 && b.size.height > 10);
const marks = finalPage.referenceMarks || [];
const overlaps = (a, b) => a.left < b.right && a.right > b.left && a.top < b.bottom && a.bottom > b.top;
let bvb = 0, mvb = 0, mvm = 0, upperOob = 0, clampedAtZero = 0;
for (let i = 0; i < realBlocks.length; i++) for (let j = i + 1; j < realBlocks.length; j++) if (overlaps(realBlocks[i].bounds, realBlocks[j].bounds)) bvb++;
for (let i = 0; i < marks.length; i++) {
  if (marks[i].position.y === 0) clampedAtZero++;
  for (const b of realBlocks) if (b.uuid !== marks[i].blockUuid && overlaps(marks[i].bounds, b.bounds)) mvb++;
  for (let j = i + 1; j < marks.length; j++) if (overlaps(marks[i].bounds, marks[j].bounds)) mvm++;
}
for (const b of realBlocks) if (b.position.y < 16800 && (b.bounds.left < pb.left || b.bounds.top < pb.top || b.bounds.right > pb.left + pb.width || b.bounds.bottom > pb.top + pb.height)) upperOob++;
for (const m of marks) if (m.position.y < 16800 && (m.bounds.left < pb.left || m.bounds.top < pb.top || m.bounds.right > pb.left + pb.width || m.bounds.bottom > pb.top + pb.height)) upperOob++;

return { page: PAGE_NAME, bvb, mvb, mvm, upperOob, clampedAtZero };
