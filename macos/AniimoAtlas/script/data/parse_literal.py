"""Read literal data from published JavaScript without executing JavaScript."""
import re,json
class Reader:
 def __init__(self,s,i=0): self.s,self.i=s,i
 def ws(self):
  while self.i<len(self.s) and self.s[self.i].isspace():self.i+=1
 def read(self):
  self.ws();s=self.s;c=s[self.i]
  if s.startswith('JSON.parse(',self.i):
   self.i+=11;v=json.loads(self.read());self.ws();assert s[self.i]==')';self.i+=1;return v
  if c in '`"\'':
   self.i+=1;out=''
   while s[self.i]!=c:
    x=s[self.i];self.i+=1
    if x=='\\':
     x=s[self.i];self.i+=1
     if x=='u':x=chr(int(s[self.i:self.i+4],16));self.i+=4
     elif x=='x':x=chr(int(s[self.i:self.i+2],16));self.i+=2
     else:x={'n':'\n','r':'\r','t':'\t','b':'\b','f':'\f'}.get(x,x)
    out+=x
   self.i+=1;return out
  if c in '{[':
   self.i+=1;d={} if c=='{' else [];end='}' if c=='{' else ']'
   while True:
    self.ws()
    if s[self.i]==end:self.i+=1;return d
    if c=='{':
     if s[self.i] in '`"\'': k=self.read()
     else:
      m=re.match(r'[\w$]+',s[self.i:]);assert m;k=m[0];self.i+=len(k)
     self.ws();assert s[self.i]==':';self.i+=1;d[str(k)]=self.read()
    else:d.append(self.read())
    self.ws()
    if s[self.i]==',':self.i+=1
    else:assert s[self.i]==end,(self.i,s[self.i:self.i+60])
  for token,value in [('!0',True),('!1',False),('true',True),('false',False),('null',None)]:
   if s.startswith(token,self.i):self.i+=len(token);return value
  m=re.match(r'-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?',s[self.i:]);assert m,(self.i,s[self.i:self.i+80]);self.i+=len(m[0]);v=float(m[0]);return int(v) if v.is_integer() else v
