extends RefCounted
## 화면 글자 도우미.

const WORD_JOINER := "⁠"


## 한글이 어절 중간("마음/이")에서 줄바꿈되지 않도록, 띄어쓰기가 아닌 글자 사이에 보이지 않는 연결 문자를 넣는다.
## 줄은 띄어쓰기에서만 바뀐다.
static func keep_words(text: String) -> String:
	var result := ""
	var count := text.length()
	for i in count:
		var character := text[i]
		result += character
		if i + 1 < count and not _is_space(character) and not _is_space(text[i + 1]):
			result += WORD_JOINER
	return result


static func _is_space(character: String) -> bool:
	return character == " " or character == "\n" or character == "\t"
