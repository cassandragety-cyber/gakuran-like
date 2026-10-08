// Calculatrice sûre (pas d'eval) : + - * / % ^, parenthèses, fonctions et constantes usuelles.
const FUNCS = {
  sqrt: Math.sqrt, abs: Math.abs, round: Math.round, floor: Math.floor, ceil: Math.ceil,
  sin: Math.sin, cos: Math.cos, tan: Math.tan, asin: Math.asin, acos: Math.acos, atan: Math.atan,
  ln: Math.log, log: Math.log10, exp: Math.exp,
};
const CONSTS = { pi: Math.PI, e: Math.E };

function evaluate(input) {
  const src = String(input).replace(/×/g, '*').replace(/÷/g, '/').replace(/,/g, '.').toLowerCase();
  let i = 0;
  const peek = () => { while (src[i] === ' ') i++; return src[i]; };
  const eat = (ch) => { if (peek() === ch) { i++; return true; } return false; };

  function expr() {
    let v = term();
    for (;;) {
      if (eat('+')) v += term();
      else if (eat('-')) v -= term();
      else return v;
    }
  }
  function term() {
    let v = factor();
    for (;;) {
      if (eat('*')) v *= factor();
      else if (eat('/')) v /= factor();
      else if (eat('%')) v %= factor();
      else return v;
    }
  }
  function factor() {
    if (eat('-')) return -factor();
    if (eat('+')) return factor();
    const base = atom();
    if (eat('^')) return base ** factor(); // associatif à droite
    return base;
  }
  function atom() {
    if (eat('(')) {
      const v = expr();
      if (!eat(')')) throw new Error('parenthèse fermante manquante');
      return v;
    }
    peek();
    const num = /^\d+(\.\d+)?/.exec(src.slice(i));
    if (num) { i += num[0].length; return parseFloat(num[0]); }
    const id = /^[a-z]+/.exec(src.slice(i));
    if (id) {
      i += id[0].length;
      if (id[0] in CONSTS) return CONSTS[id[0]];
      if (id[0] in FUNCS) {
        if (!eat('(')) throw new Error(`« ${id[0]} » attend des parenthèses`);
        const v = expr();
        if (!eat(')')) throw new Error('parenthèse fermante manquante');
        return FUNCS[id[0]](v);
      }
      throw new Error(`inconnu : ${id[0]}`);
    }
    throw new Error(`caractère inattendu : ${src[i] ?? 'fin'}`);
  }

  const result = expr();
  if (peek() !== undefined) throw new Error(`caractère inattendu : ${src[i]}`);
  return result;
}

module.exports = { evaluate };
