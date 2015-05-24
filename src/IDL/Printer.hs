module IDL.Printer (ppPureScriptFFI) where

import Data.List (nubBy, sort)
import Data.Maybe (isNothing)
import Text.PrettyPrint (Doc, ($+$), ($$), (<>), (<+>), brackets, char, space,
  hcat, punctuate, semi, lbrace, rbrace, empty, parens, nest, integer, text,
  vcat)

import IDL.AST

ppPureScriptFFI :: Idl -> Doc
ppPureScriptFFI idl =
        header    $+$ blankLine
    $+$ typeDecls $+$ blankLine
    $+$ constants $+$ blankLine
    $+$ methods   $+$ blankLine
  where
    -- TODO: these need some heavy cleanup
    header = vcat . map text $ moduleHeader ++ [""] ++ typedefs
    typeDecls = vcat $ map ppTypeDecl $ sort $ nubBy (\t1 t2-> typeName t1 == typeName t2)
                    [t  | d <- idl, t <- extractTypes d, not ((typeName t) `elem` webglTypes)]
    constants = vcat [ppConstant c | c <- idl , isEnum c]
    methods = vcat $ map ppFuncImpl $ nubBy (\t1 t2-> methodName t1 == methodName t2)
                    [c | c <- idl , isUsableFunc c]

-- predefined strings

moduleHeader :: [String]
moduleHeader =
    [ "-- This file is automatically generated! Don't edit this file, but"
    , "-- instead modify purescript-webgl-generator."
    , ""
    , "module Graphics.WebGL.Raw where"
    , ""
    , "import Control.Monad.Eff"
    , "import Control.Monad.Eff.WebGL"
    , "import Data.ArrayBuffer.Types"
    , "import Data.TypedArray"
    ]

typedefs :: [String]
typedefs =
    [ "type GLenum     = Number"
    , "type GLboolean  = Boolean"
    , "type GLbitfield = Number"
    , "type GLbyte     = Number"
    , "type GLshort    = Number"
    , "type GLint      = Number"
    , "type GLsizei    = Number"
    , "type GLintptr   = Number"
    , "type GLsizeiptr = Number"
    , "type GLubyte    = Number"
    , "type GLushort   = Number"
    , "type GLuint     = Number"
    , "type GLfloat    = Number"
    , "type GLclampf   = Number"
    , "type FloatArray = Float32Array"
    ]

webglTypes :: [String]
webglTypes =
    [ "ArrayBuffer"
    , "DOMString"
    , "Float32Array"
    , "FloatArray"
    , "GLbitfield"
    , "GLboolean"
    , "GLbyte"
    , "GLclampf"
    , "GLenum"
    , "GLfloat"
    , "GLint"
    , "GLintptr"
    , "GLshort"
    , "GLsizei"
    , "GLsizeiptr"
    , "GLubyte"
    , "GLuint"
    , "GLushort"
    , "HTMLCanvasElement"
    , "Int32Array"
    , "any"
    , "boolean"
    , "object"
    , "sequence"
    , "void"
    ]

-- component pretty-printers

ppConstant :: Decl -> Doc
ppConstant Enum { enumName = n, enumValue = v } =
    text constName <+> text "=" $$ nest 48 (integer v)
  where
    constName = '_' : n

ppTypeSig :: Decl -> Doc
ppTypeSig f
    | hasGenericReturnType =
        text ":: forall eff a." <+> argList <+> effMonad (char 'a')
    | otherwise =
        text ":: forall eff." <+> argList <+> effMonad (ppType $ methodRetType f)
  where
    hasGenericReturnType =
      typeName (methodRetType f) `elem` ["any", "object"]
    effMonad doc =
      parens $ text "Eff (canvas :: Canvas | eff)" <+> doc
    argList =
      text "Fn" <>
      text (show . length $ funcArgs f) <+>
      hcat (punctuate space (map (ppType . argType) (funcArgs f)))

ppMethod :: Decl -> Doc
ppMethod f =
    prefixWebgl <> text (methodName f) <> parens (ppArgs methodArgs f) <> semi

ppFuncImplBody :: Decl -> Doc
ppFuncImplBody f =
    func <+> text (implName f) <> parens (ppArgs funcArgs f) <+> lbrace $+$
    nest 2 (ret <+> func <+> parens empty <+> lbrace) $+$
    nest 4 (ret <+> ppMethod f) $+$
    nest 2 rbrace <> semi $+$
    rbrace
  where
    func = text "function"
    ret  = text "return"

ppArgs :: (Decl -> [Arg]) -> Decl -> Doc
ppArgs f = hcat . punctuate (text ", ") . map (text . argName) . f

ppFuncImpl :: Decl -> Doc
ppFuncImpl f =
    text "foreign import" <+> text (implName f) <+>
    jsBlock $+$ nest 2 (ppFuncImplBody f) $+$ jsBlock <+>
    ppTypeSig f $+$ blankLine
  where
    jsBlock = text "\"\"\""

ppTypeDecl :: Type -> Doc
ppTypeDecl d = text "foreign import data" <+> text (typeName d) <+> text ":: *"

ppType :: Type -> Doc
ppType Type { typeName = name, typeIsArray = isArray }
    | name == "void"        = toType "Unit"
    | name == "boolean"     = toType "Boolean"
    | name == "DOMString"   = toType "String"
    | name == "ArrayBuffer" = toType "Float32Array"
    | otherwise             = toType name
  where
    toType = if isArray then brackets . text else text

-- helpers

blankLine :: Doc
blankLine = text ""

extractTypes :: Decl -> [Type]
extractTypes f@Function{methodRetType = t1} = t1 : map argType (funcArgs f)
extractTypes Attribute{attType = t1} = [t1]
extractTypes _ = []

isUsableFunc :: Decl -> Bool
isUsableFunc i =
    isFunction i &&
    and (map (isNothing . typeCondPara . argType) $ methodArgs i)

implName :: Decl -> String
implName f = methodName f ++ "Impl"

funcArgs :: Decl -> [Arg]
funcArgs f = webglContext : methodArgs f

webglContext :: Arg
webglContext = Arg (Type "WebGLContext" False Nothing) "webgl"

prefixWebgl :: Doc
prefixWebgl = text (argName webglContext) <> text "."
