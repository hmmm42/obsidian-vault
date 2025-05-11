# 四种旋转逻辑
```go
// rotateAt 辅助函数，在节点 g 处进行旋转修复，返回调整后的子树新根
func (t *AVLTree) rotateAt(g *Node) *Node {
	// g 节点已经确定是失衡的 (|balance| > 1)
	balance := t.getBalanceFactor(g)
	
	if balance > 1 { // 左子树更高 (LL 或 LR)
		p := g.Left // 失衡点的左子节点
		// 检查 p 的平衡因子
		if t.getBalanceFactor(p) >= 0 { // p 的左子树更高或相等 (LL 情况)
			// 对 g 进行右旋
			return t.rotateRight(g)
		} else { // p 的右子树更高 (LR 情况)
			// 先对 p 进行左旋
			t.rotateLeft(p) // rotateLeft 会更新 p 及其原右子节点的高度和父指针
			// 再对 g 进行右旋
			return t.rotateRight(g) // rotateRight 会更新 g 及其原左子节点（现在是 p 左旋后的新根）的高度和父指针
		}
	} else { // 右子树更高 (RR 或 RL)
		p := g.Right // 失衡点的右子节点
		// 检查 p 的平衡因子
		if t.getBalanceFactor(p) <= 0 { // p 的右子树更高或相等 (RR 情况)
			// 对 g 进行左旋
			return t.rotateLeft(g)
		} else { // p 的左子树更高 (RL 情况)
			// 先对 p 进行右旋
			t.rotateRight(p) // rotateRight 会更新 p 及其原左子节点的高度和父指针
			// 再对 g 进行左旋
			return t.rotateLeft(g) // rotateLeft 会更新 g 及其原右子节点（现在是 p 右旋后的新根）的高度和父指针
		}
	}
}

```
# 递归ver.
```go

// //////// 递归插入 (使用 rotateAt 优化) //////////

// Insert 插入一个值
func (t *AVLTree) Insert(value int) {
	t.Root = t.insertNode(t.Root, value)
}

// insertNode 辅助函数，递归插入节点并进行平衡修复 (使用 rotateAt)
func (t *AVLTree) insertNode(node *Node, value int) *Node {
	// 1. 执行标准的 BST 插入
	if node == nil {
		return &Node{Value: value, Height: 0} // 新节点高度为 0
	}
	
	if value < node.Value {
		node.Left = t.insertNode(node.Left, value)
	} else if value > node.Value {
		node.Right = t.insertNode(node.Right, value)
	} else {
		return node // 值已存在，不做处理
	}
	
	// 2. 更新当前节点的高度
	// 在递归调用返回后，子节点的高度已经被更新或通过旋转修复好了
	t.updateHeight(node)
	
	// 3. 检查当前节点是否失衡
	if !t.isBalanced(node) {
		// 如果失衡，调用 rotateAt 进行平衡修复并返回新的子树根
		return t.rotateAt(node)
	}
	
	// 4. 未失衡，返回当前节点
	return node
}

// //////// 递归删除 (使用 rotateAt 优化) //////////

// Search 查找一个值 (沿用迭代实现，也可以是递归)
func (t *AVLTree) Search(value int) *Node {
	current := t.Root
	for current != nil {
		if value == current.Value {
			return current
		} else if value < current.Value {
			current = current.Left
		} else {
			current = current.Right
		}
	}
	return nil
}

// Delete 删除一个值
func (t *AVLTree) Delete(value int) {
	t.Root = t.deleteNode(t.Root, value)
}

// deleteNode 辅助函数，递归删除节点并进行平衡修复 (使用 rotateAt)
func (t *AVLTree) deleteNode(node *Node, value int) *Node {
	// 1. 执行标准的 BST 删除
	if node == nil {
		return nil // 未找到要删除的节点
	}
	
	if value < node.Value {
		node.Left = t.deleteNode(node.Left, value)
	} else if value > node.Value {
		node.Right = t.deleteNode(node.Right, value)
	} else { // 找到了要删除的节点
		// 情况 1: 节点是叶子节点或只有一个子节点
		if node.Left == nil {
			return node.Right // 返回右子节点 (可能为 nil)
		} else if node.Right == nil {
			return node.Left // 返回左子节点
		}
		
		// 情况 2: 节点有两个子节点
		// 找到右子树中的最小节点 (即中序后继)
		minNode := t.minimum(node.Right)
		// 将当前节点的值替换为中序后继的值
		node.Value = minNode.Value
		// 递归删除中序后继节点 (它一定没有左子节点)
		node.Right = t.deleteNode(node.Right, minNode.Value)
		// 注意：删除中序后继后，其右子树可能需要平衡调整，递归调用会处理
	}
	
	// 如果当前节点在删除后变成了 nil (例如删除了叶子节点)，则无需平衡处理，直接返回 nil
	if node == nil {
		return nil
	}
	
	// 2. 更新当前节点的高度
	// 在子树删除并递归返回后，子树的高度可能已经变化或通过旋转修复了
	t.updateHeight(node)
	
	// 3. 检查当前节点是否失衡
	if !t.isBalanced(node) {
		// 如果失衡，调用 rotateAt 进行平衡修复并返回新的子树根
		return t.rotateAt(node)
	}
	
	// 4. 未失衡，返回当前节点
	return node
}

// minimum 查找以 node 为根的子树中的最小节点 (用于删除)
func (t *AVLTree) minimum(node *Node) *Node {
	current := node
	for current.Left != nil {
		current = current.Left
	}
	return current
}


```

# 迭代ver.
```go
// //////// 迭代插入 //////////

// Insert 插入一个值 (迭代实现)
func (t *AVLTree) Insert(value int) {
	newNode := &Node{Value: value, Height: 0} // 新节点高度为 0
	
	if t.Root == nil {
		t.Root = newNode
		return
	}
	
	// 1. 执行标准的 BST 迭代插入，并记录路径上的父节点
	var parent *Node
	current := t.Root
	
	for current != nil {
		parent = current // 记录父节点
		if value < current.Value {
			current = current.Left
		} else if value > current.Value {
			current = current.Right
		} else {
			// 值已存在，不做处理
			return
		}
	}
	
	// 将新节点连接到父节点
	newNode.Parent = parent
	if value < parent.Value {
		parent.Left = newNode
	} else {
		parent.Right = newNode
	}
	
	// 2. 从新插入节点的父节点开始，向上回溯并进行平衡调整
	// g 从新插入节点的父节点开始
	g := parent
	
	for g != nil {
		// 保存 g 的父节点，因为 rotateAt 可能会改变 g 的父指针
		p := g.Parent
		
		// 更新当前节点的高度
		t.updateHeight(g)
		
		// 检查平衡
		if !t.isBalanced(g) {
			// 如果失衡，进行旋转修复
			// rotateAt 会处理旋转，并更新相关节点的高度和父指针
			// 它返回的是调整后子树的新根
			newRoot := t.rotateAt(g)
			
			// 如果 p 不为 nil，将 p 的子节点指向新的子树根
			// 如果 p 为 nil，说明 g 是原树根，新根成为树的根
			// rotateAt 已经处理了 newRoot 的 Parent 指针指向 p
			if p == nil {
				t.Root = newRoot
			}
			// 注意：rotateAt 内部已经处理了 p 的子节点指针指向 newRoot，这里无需额外处理
			// 除非 rotateAt 不处理父指针，那样这里就需要判断 newRoot 是 p 的左子还是右子并链接
			
			// 这里的 g 仍然指向旋转前的那个节点，但它已经不是回溯路径上的节点了
			// 我们下一轮循环应该从 p 继续向上
			g = p // 向上移动到原 g 的父节点
			// 注意：因为旋转可能改变了 g 的父指针，所以必须使用之前保存的 p
			continue // 旋转后，这个节点 g 的平衡已经修复（由 rotateAt 保证），直接跳到下一轮检查 p
		}
		
		// 如果平衡，检查高度是否变化，如果高度没有变化，说明更高层的祖先节点也不会失衡，可以提前终止
		// 这里的逻辑可以参考 C++ 代码片段，如果平衡因子为 0，表示高度可能没变
		// 但更准确的判断是比较 updateHeight 前后的高度，这里简化为检查平衡因子是否为 0
		if t.getBalanceFactor(g) == 0 {
			break // 高度未变，提前终止
		}
		
		// 向上移动到父节点
		g = p // g = g.Parent 在 rotateAt 改变 g.Parent 后会出错，所以使用 p
	}
}

// //////// 迭代删除 //////////

// Delete 删除一个值 (迭代实现)
func (t *AVLTree) Delete(value int) {
	// 1. 执行标准的 BST 迭代删除
	// 需要找到要删除的节点 z 及其父节点 parentZ
	// 如果 z 有两个子节点，还需要找到中序后继 y 及其父节点 parentY
	var z, parentZ *Node
	current := t.Root
	parentZ = nil
	
	// 查找要删除的节点 z
	for current != nil {
		if value == current.Value {
			z = current
			break
		}
		parentZ = current
		if value < current.Value {
			current = current.Left
		} else {
			current = current.Right
		}
	}
	
	if z == nil {
		// fmt.Printf("值 %d 未找到，无法删除\n", value)
		return // 未找到要删除的节点
	}
	
	// nodeToDelete 是实际将要从树中移除的节点 (要么是 z，要么是 z 的中序后继)
	// startNode 是我们向上回溯检查平衡的起点 (nodeToDelete 的父节点)
	var nodeToDelete *Node
	var startNode *Node
	
	if z.Left == nil || z.Right == nil {
		// 情况 1: z 没有左子节点或没有右子节点 (包括是叶子节点)
		nodeToDelete = z
		startNode = parentZ // 回溯从 z 的父节点开始
		
		// 用 z 的非空子节点替换 z 的位置
		var child *Node
		if z.Left != nil {
			child = z.Left
		} else {
			child = z.Right // 可能为 nil
		}
		
		if parentZ == nil { // 如果 z 是根节点
			t.Root = child
			if child != nil {
				child.Parent = nil // 新根的父节点为 nil
			}
		} else if parentZ.Left == z {
			parentZ.Left = child
			if child != nil {
				child.Parent = parentZ
			}
		} else { // parentZ.Right == z
			parentZ.Right = child
			if child != nil {
				child.Parent = parentZ
			}
		}
		
	} else {
		// 情况 2: z 有两个子节点
		// 找到 z 的中序后继 y (右子树中的最小节点)
		var y, parentY *Node
		y = z.Right
		parentY = z // y 的父节点，初始是 z
		
		for y.Left != nil {
			parentY = y
			y = y.Left
		}
		
		nodeToDelete = y // 实际要移除的是中序后继 y
		startNode = parentY // 回溯从 y 的父节点开始
		
		// 用 y 的右子节点替换 y 的位置 (y 一定没有左子节点)
		var yRightChild = y.Right // y 的右子节点 (可能为 nil)
		
		if parentY.Left == y { // 如果 y 是其父节点 (parentY) 的左子节点
			parentY.Left = yRightChild
		} else { // 如果 y 是其父节点 (parentY) 的右子节点 (说明 parentY 就是 z)
			parentY.Right = yRightChild
		}
		
		if yRightChild != nil {
			yRightChild.Parent = parentY // y 的右子节点的父节点更新为 parentY
		}
		
		// 将 y 的值复制给 z (逻辑上删除了 z，物理上删除了 y)
		z.Value = y.Value
		
		// 注意：这里我们逻辑上删除了 z，物理上删除了 y。
		// 需要从 parentY 开始向上回溯检查，因为 y 的删除可能导致 parentY 失衡。
		// 如果 parentY 就是 z (也就是 y 是 z 的直接右子节点)，那么回溯点仍然是 parentY。
	}
	
	// 如果删除后树为空，则无需回溯
	if t.Root == nil {
		return
	}
	
	// 如果 startNode 在上面的逻辑中被设置为 nil (例如删除了单节点的根)，
	// 那么回溯点应该从新的根节点开始（如果存在的话），否则树为空。
	// 这里的逻辑需要小心。如果我们从被删除节点的父节点开始回溯，
	// 如果删除的是根节点且有子节点，startNode 会是 nil，回溯循环不会执行。
	// 一个更稳健的方法是，总是从树根开始向上找到第一个需要调整的祖先。
	// 但为了遵循 C++ 代码片段的“从父节点开始向上”的模式，我们使用 startNode。
	// 如果 startNode 是 nil 且 Root 不为 nil (删除了根且有子节点)，回溯应该从 Root 开始。
	if startNode == nil && t.Root != nil {
		startNode = t.Root // 如果删除了根节点且有子节点，从新的根开始回溯
	}
	
	
	// 2. 从 startNode 开始，向上回溯并进行平衡调整
	g := startNode
	
	for g != nil {
		// 保存 g 的父节点
		p := g.Parent
		
		// 更新当前节点的高度
		oldHeight := g.Height // 保存旧高度以便后续判断
		t.updateHeight(g)
		
		// 检查平衡
		if !t.isBalanced(g) {
			// 如果失衡，进行旋转修复
			newRoot := t.rotateAt(g)
			
			// RotateAt 已经更新了 newRoot 的 Parent 指针指向 p
			// 如果 p 不为 nil，链接 p 的子节点到 newRoot
			// 如果 p 为 nil，newRoot 就是新的树根 (rotateAt 已处理)
			if p != nil {
				if p.Left == g {
					p.Left = newRoot
				} else {
					p.Right = newRoot
				}
				// newRoot.Parent 在 rotateAt 中已设置为 p
			} else {
				// g 原来是根，rotateAt 已经设置了 t.Root = newRoot 且 newRoot.Parent = nil
				// 确保 Root 正确
				t.Root = newRoot
			}
			
			// 这里的 g 仍然指向旋转前的节点，下一轮循环应该从 p 继续向上
			g = p // 向上移动到原 g 的父节点
			// 不需要像插入那样 continue，因为删除可能导致上层节点也失衡
			// 但如果旋转后，新子树根的高度等于旋转前 g 的高度，说明高度变化没有向上影响，可以 break
			// 这里简化，不 break，总是回溯到根，确保所有祖先都检查到
			
		} else { // 如果平衡
			// 检查高度是否变化。如果高度没有变化，说明上层祖先节点不会因为这里的删除而失衡，可以提前终止回溯。
			// 这是删除操作的一个重要优化。
			if g.Height == oldHeight {
				break // 高度未变，提前终止回溯
			}
			// 如果高度变化了，即使当前平衡，也需要继续向上检查父节点
		}
		
		// 向上移动到父节点
		g = p
	}
}

```