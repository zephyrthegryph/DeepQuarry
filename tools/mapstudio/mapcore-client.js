/* Direct browser binding to the same Rust topology used by the map server. */
class MapcoreClient {
  constructor() { this.exports=null; this.loading=null; this.encoder=new TextEncoder(); this.decoder=new TextDecoder(); }
  load() {
    if (!this.loading) this.loading=WebAssembly.instantiateStreaming(fetch('/mapcore.wasm'))
      .then((module) => {this.exports=module.instance.exports;return true;})
      .catch((error) => {console.warn('Local Rust previews unavailable:',error);return false;});
    return this.loading;
  }
  route(operation, tileAt, loaded) {
    if (!this.exports) return null;
    const tiles=[];
    const seen=new Set();
    for (const point of operation.points) {
      const id=`${point.x},${point.y},${point.z}`;
      if (seen.has(id)) continue;
      if (!loaded(point)) return null;
      seen.add(id);
      tiles.push({...point,atoms:tileAt(point)});
    }
    const input=this.encoder.encode(JSON.stringify({...operation,tiles}));
    const ptr=this.exports.mapcore_alloc(input.length);
    if (!ptr) throw Error('Rust preview allocation failed');
    try {
      new Uint8Array(this.exports.memory.buffer,ptr,input.length).set(input);
      const result=this.exports.mapcore_route(ptr,input.length);
      if (!result) throw Error('Rust preview failed');
      try {
        const view=new DataView(this.exports.memory.buffer);
        const length=view.getUint32(result,true);
        const bytes=new Uint8Array(this.exports.memory.buffer,result+4,length);
        const value=JSON.parse(this.decoder.decode(bytes));
        if (value.error) throw Error(value.error);
        return value;
      } finally {
        const length=new DataView(this.exports.memory.buffer).getUint32(result,true);
        this.exports.mapcore_free(result,length+4);
      }
    } finally {this.exports.mapcore_free(ptr,input.length);}
  }
}
