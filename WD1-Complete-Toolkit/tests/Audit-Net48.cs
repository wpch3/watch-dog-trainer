// Development-only metadata auditor. Requires Mono.Cecil for this test tool, not for WD1-Toolkit.
// Reads the emitted EXE; resolves framework MemberRefs only against the supplied Microsoft net48 reference directory.
using System;
using System.IO;
using System.Collections.Generic;
using System.Linq;
using Mono.Cecil;
class Net48Audit {
 sealed class RefOnlyResolver:IAssemblyResolver {
  readonly string directory;readonly Dictionary<string,AssemblyDefinition> loaded=new Dictionary<string,AssemblyDefinition>();
  public RefOnlyResolver(string dir){directory=Path.GetFullPath(dir);}
  public AssemblyDefinition Resolve(AssemblyNameReference name){return Resolve(name,new ReaderParameters());}
  public AssemblyDefinition Resolve(AssemblyNameReference name,ReaderParameters ignored){
   AssemblyDefinition a;if(loaded.TryGetValue(name.Name,out a))return a;
   string path=Path.Combine(directory,name.Name+".dll");if(!File.Exists(path))path=Path.Combine(directory,"Facades",name.Name+".dll");
   if(!File.Exists(path))throw new AssemblyResolutionException(name);
   a=AssemblyDefinition.ReadAssembly(path,new ReaderParameters{AssemblyResolver=this});loaded.Add(name.Name,a);return a;
  }
  public void Dispose(){foreach(var a in loaded.Values)a.Dispose();loaded.Clear();}
 }
 static string Signature(MemberReference member){return member.FullName;}
 static int Main(string[] args){
  if(args.Length!=2){Console.Error.WriteLine("Audit-Net48.exe <application.exe> <Microsoft .NETFramework/v4.8 refs>");return 2;}
  int checkedCount=0,missing=0,intrinsics=0;
  using(var resolver=new RefOnlyResolver(args[1]))
  using(var app=AssemblyDefinition.ReadAssembly(args[0],new ReaderParameters{AssemblyResolver=resolver})){
   foreach(var m in app.MainModule.GetMemberReferences()){
    var scope=m.DeclaringType.Scope as AssemblyNameReference;if(scope==null)continue;
    if(m.DeclaringType is ArrayType){intrinsics++;continue;}
    checkedCount++;bool ok=false;
    try{var method=m as MethodReference;var field=m as FieldReference;
     if(method!=null)ok=method.Resolve()!=null;else if(field!=null)ok=field.Resolve()!=null;
    }catch(AssemblyResolutionException){}catch(ResolutionException){}
    if(!ok){Console.WriteLine("MISSING "+scope.Name+": "+Signature(m));missing++;}
   }
   foreach(var a in app.MainModule.AssemblyReferences)Console.WriteLine("REF "+a.FullName);
   foreach(var a in app.CustomAttributes)if(a.AttributeType.FullName=="System.Runtime.Versioning.TargetFrameworkAttribute")Console.WriteLine("TFM "+a.ConstructorArguments[0].Value);
  }
  Console.WriteLine("NET48_MEMBERREFS_CHECKED="+checkedCount);Console.WriteLine("ARRAY_INTRINSICS="+intrinsics);Console.WriteLine("NET48_MISSING="+missing);
  return missing==0?0:1;
 }
}
